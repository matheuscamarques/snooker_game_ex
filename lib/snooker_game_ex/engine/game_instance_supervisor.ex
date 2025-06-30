defmodule SnookerGameEx.Engine.GameInstanceSupervisor do
  @moduledoc "ADAPTER: Supervisor para uma única instância de jogo."
  use Supervisor

  alias SnookerGameEx.Engine.{CollisionEngine, ParticleSupervisor}

  def start_link(game_id) do
    Supervisor.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def via_tuple(game_id), do: {:via, Registry, {SnookerGameEx.GameRegistry, game_id}}

  @impl true
  def init(game_id) do
    ets_table_tid =
      :ets.new(:game_ets_table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Injeta o notificador aqui, para que todos os filhos o recebam.
    notifier = SnookerGameEx.Notifiers.PubSubNotifier

    children = [
      {CollisionEngine, game_id: game_id, ets_table: ets_table_tid, notifier: notifier},
      {ParticleSupervisor, game_id: game_id, ets_table: ets_table_tid, notifier: notifier}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def restart(game_id) do
    case Registry.lookup(SnookerGameEx.GameRegistry, game_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(SnookerGameEx.Engine.GameSupervisor, pid)

      [] ->
        :ok
    end
  end
end
