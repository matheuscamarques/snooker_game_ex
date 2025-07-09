defmodule SnookerGameEx.Core.GameRules do
  @moduledoc "Define a struct de dados pura para o estado das regras de um jogo."
  defstruct game_phase: :break,
            current_turn: :player1,
            ball_assignments: %{},
            pocketed_in_turn: [],
            pocketed_balls: [],
            # Flag geral de falta no turno
            foul_committed: false,
            # Flag específica para permitir o reposicionamento
            ball_in_hand: false,
            winner: nil,
            status_message: "Quebra inicial! Jogador 1 começa.",
            can_shoot: true,
            scores: %{player1: 0, player2: 0}
end
