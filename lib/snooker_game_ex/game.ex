defmodule SnookerGameEx.Game do
  @moduledoc """
  O Port de ENTRADA (Driving Port) que define a API para controlar um jogo.
  Qualquer adaptador externo (como um Channel ou um teste) usa este contrato.
  """

  @doc "Inicia uma nova instância de jogo."
  @callback start_game(game_id :: String.t()) :: :ok

  @doc "Aplica uma força a uma partícula específica no jogo."
  @callback apply_force(game_id :: String.t(), particle_id :: any(), force :: {float(), float()}) ::
              :ok

  @doc "Para uma partícula."
  @callback hold_ball(game_id :: String.t(), particle_id :: any()) :: :ok

  @doc "Reinicia um jogo, retornando todas as partículas ao estado inicial."
  @callback restart_game(game_id :: String.t()) :: :ok
end
