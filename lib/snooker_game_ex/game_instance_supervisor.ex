defmodule SnookerGameEx.GameInstanceSupervisor do
  @moduledoc """
  Supervisor para uma única instância de um jogo de sinuca.
  Gerencia o CollisionEngine e o ParticleSupervisor para um jogo específico.
  Esta versão usa identificadores de tabela ETS (tids) para evitar vazamentos de memória de átomos.
  """
  use Supervisor

  def start_link(game_id) do
    Supervisor.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def via_tuple(game_id), do: {:via, Registry, {SnookerGameEx.GameRegistry, game_id}}

  @impl true
  def init(game_id) do
    # SOLUÇÃO 1: Criar a tabela sem um nome de átomo dinâmico.
    # `:ets.new` retorna um identificador de tabela (tid) que é seguro para usar e é coletado pelo garbage collector.
    # O primeiro argumento é um nome apenas para fins de depuração em observadores, não para acesso.
    ets_table_tid =
      :ets.new(:game_ets_table, [:set, :public, read_concurrency: true, write_concurrency: true])

    children = [
      # Passa o tid seguro para os processos filhos.
      {SnookerGameEx.CollisionEngine, game_id: game_id, ets_table: ets_table_tid},
      {SnookerGameEx.ParticleSupervisor, game_id: game_id, ets_table: ets_table_tid}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Reinicia uma instância de jogo terminando seu processo supervisor.
  O `GameSupervisor` (DynamicSupervisor) o recriará quando for solicitado novamente.
  """
  def restart(game_id) do
    case Registry.lookup(SnookerGameEx.GameRegistry, game_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(SnookerGameEx.GameSupervisor, pid)

      [] ->
        :ok
    end
  end
end
