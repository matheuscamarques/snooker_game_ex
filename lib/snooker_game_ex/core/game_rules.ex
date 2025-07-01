defmodule SnookerGameEx.Core.GameRules do
  @moduledoc "Define a struct de dados pura para o estado das regras de um jogo."
  defstruct game_phase: :break,
            current_turn: :player1,
            ball_assignments: %{},
            pocketed_in_turn: [],
            first_hit_valid: true,
            winner: nil,
            status_message: "Quebra inicial! Jogador 1 começa."
end
