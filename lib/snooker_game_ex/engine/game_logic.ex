defmodule SnookerGameEx.Engine.GameLogic do
  @moduledoc "GenServer que gerencia o estado e as regras de uma instância de jogo."
  use GenServer
  require Logger

  alias SnookerGameEx.GameNotifier
  alias SnookerGameEx.Engine.Particle

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via_tuple(Keyword.fetch!(opts, :game_id)))

  def via_tuple(game_id),
    do: {:via, Registry, {SnookerGameEx.GameRegistry, {__MODULE__, game_id}}}

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    notifier = Keyword.fetch!(opts, :notifier)
    rules_module = Keyword.fetch!(opts, :rules)

    Logger.info("GameLogic started for #{game_id} with rules #{rules_module}")
    Phoenix.PubSub.subscribe(SnookerGameEx.PubSub, "game_events:#{game_id}")

    initial_rules_state = rules_module.init()

    state = %{
      game_id: game_id,
      notifier: notifier,
      rules_module: rules_module,
      rules_state: initial_rules_state
    }

    notifier.notify_game_state_update(game_id, initial_rules_state)
    {:ok, state}
  end

  @impl true
  def handle_cast(:start_shot, state) do
    new_rules_state = %{state.rules_state | can_shoot: false}
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  @impl true
  def handle_cast({:reposition_cue_ball, new_pos}, state) do
    Logger.debug("[Game #{state.game_id}] Repositioning cue ball to #{inspect(new_pos)}.")
    Particle.reposition(state.game_id, 0, new_pos)
    new_rules_state = state.rules_module.handle_ball_reposition(state.rules_state)
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  @impl true
  def handle_info({:ball_pocketed, _particle_id, ball_data}, state) do
    Logger.debug("[Game #{state.game_id}] Ball pocketed: #{inspect(ball_data)}")
    new_rules_state = state.rules_module.handle_ball_pocketed(state.rules_state, ball_data)
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  # --- CORREÇÃO PRINCIPAL AQUI ---
  @impl true
  def handle_info(:all_balls_stopped, state) do
    Logger.debug("[Game #{state.game_id}] All balls stopped, evaluating turn.")

    # A lógica foi simplificada. Agora, apenas delegamos ao módulo de regras.
    # O módulo de regras é o único responsável por determinar o estado `can_shoot`.
    # Isso corrige o bug onde o estado inicial `can_shoot: true` era incorretamente
    # alterado para `false` antes da primeira jogada.
    new_rules_state = state.rules_module.handle_turn_end(state.rules_state)

    # Notifica a UI sobre a mudança de estado retornada pelo módulo de regras.
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}
end
