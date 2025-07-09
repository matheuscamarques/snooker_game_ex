defmodule SnookerGameEx.Game do
  @moduledoc "O Port de ENTRADA (Driving Port) que define a API para controlar um jogo."

  @doc "Inicia uma nova instância de jogo."
  @callback start_game(game_id :: String.t()) :: :ok

  @doc "Inicia a ação de uma tacada, bloqueando novas tacadas."
  @callback start_shot(game_id :: String.t()) :: :ok

  @doc "Aplica uma força a uma partícula específica no jogo."
  @callback apply_force(game_id :: String.t(), particle_id :: any(), force :: {float(), float()}) ::
              :ok

  # NOVO: Define a nova função na interface pública do jogo.
  @doc "Reposiciona a bola branca para uma nova posição após uma falta."
  @callback reposition_cue_ball(game_id :: String.t(), pos :: {float(), float()}) :: :ok

  @doc "Reinicia um jogo, retornando todas as partículas ao estado inicial."
  @callback restart_game(game_id :: String.t()) :: :ok
end
