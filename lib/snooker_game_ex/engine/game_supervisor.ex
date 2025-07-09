defmodule SnookerGameEx.Engine.GameSupervisor do
  @moduledoc "ADAPTER: Supervisor dinâmico para todas as instâncias de jogo."
  use DynamicSupervisor

  @behaviour SnookerGameEx.Game

  alias SnookerGameEx.Engine.GameInstanceSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # --- Implementação do Port `Game` ---

  @impl SnookerGameEx.Game
  def start_game(game_id) do
    case Registry.lookup(SnookerGameEx.GameRegistry, game_id) do
      [] ->
        spec = {GameInstanceSupervisor, game_id}
        DynamicSupervisor.start_child(__MODULE__, spec)

      _ ->
        {:ok, :already_started}
    end
  end

  @impl SnookerGameEx.Game
  def start_shot(game_id) do
    case Registry.lookup(SnookerGameEx.GameRegistry, {SnookerGameEx.Engine.GameLogic, game_id}) do
      [{pid, _}] -> GenServer.cast(pid, :start_shot)
      [] -> {:error, :game_not_found}
    end
  end

  @impl SnookerGameEx.Game
  def apply_force(game_id, particle_id, force) do
    case Registry.lookup(
           SnookerGameEx.GameRegistry,
           {SnookerGameEx.Engine.CollisionEngine, game_id}
         ) do
      [{pid, _}] -> GenServer.cast(pid, {:apply_force, particle_id, force})
      [] -> {:error, :game_not_found}
    end
  end

  # NOVO: Implementação da função do port.
  @impl SnookerGameEx.Game
  def reposition_cue_ball(game_id, {x, y}) do
    case Registry.lookup(SnookerGameEx.GameRegistry, {SnookerGameEx.Engine.GameLogic, game_id}) do
      [{pid, _}] -> GenServer.cast(pid, {:reposition_cue_ball, [x, y]})
      [] -> {:error, :game_not_found}
    end
  end

  @impl SnookerGameEx.Game
  def restart_game(game_id) do
    GameInstanceSupervisor.restart(game_id)
    :ok
  end
end
