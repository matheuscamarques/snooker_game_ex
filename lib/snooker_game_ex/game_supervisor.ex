defmodule SnookerGameEx.GameSupervisor do
  @moduledoc """
  Um supervisor dinâmico que gerencia o ciclo de vida de todas as instâncias de jogos.
  Cada jogo é executado em sua própria árvore de supervisão para garantir o isolamento.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Inicia uma nova instância de jogo para o game_id fornecido, a menos que já exista.
  """
  def start_game(game_id) do
    # Usa um registro para verificar se o jogo já está em execução para evitar race conditions
    case Registry.lookup(SnookerGameEx.GameRegistry, game_id) do
      [] ->
        spec = {SnookerGameEx.GameInstanceSupervisor, game_id}
        DynamicSupervisor.start_child(__MODULE__, spec)

      _ ->
        # O jogo já está em execução, não faz nada
        :ok
    end
  end
end
