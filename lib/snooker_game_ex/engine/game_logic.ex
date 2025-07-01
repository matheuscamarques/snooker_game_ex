defmodule SnookerGameEx.Engine.GameLogic do
  @moduledoc "GenServer que gerencia o estado e as regras de uma instância de jogo."
  use GenServer
  require Logger

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
  def handle_info({:ball_pocketed, _particle_id, ball_data}, state) do
    new_rules_state = state.rules_module.handle_ball_pocketed(state.rules_state, ball_data)
    ## CORREÇÃO: Notificar a UI imediatamente sobre a mudança de estado das regras.
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  @impl true
  def handle_info(:all_balls_stopped, state) do
    Logger.debug("[Game #{state.game_id}] All balls stopped, evaluating turn.")
    new_rules_state = state.rules_module.handle_turn_end(state.rules_state)
    state.notifier.notify_game_state_update(state.game_id, new_rules_state)
    {:noreply, %{state | rules_state: new_rules_state}}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}
end
