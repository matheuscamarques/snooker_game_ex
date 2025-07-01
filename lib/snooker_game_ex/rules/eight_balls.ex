defmodule SnookerGameEx.Rules.EightBall do
  @moduledoc "Implementação das regras do Bola 8."
  @behaviour SnookerGameEx.Rules
  alias SnookerGameEx.Core.GameRules

  @impl SnookerGameEx.Rules
  def init(), do: %GameRules{}

  @impl SnookerGameEx.Rules
  def handle_ball_pocketed(state, ball_data),
    do: update_in(state, [:pocketed_in_turn], &[ball_data | &1])

  @impl SnookerGameEx.Rules
  def handle_turn_end(state) do
    final_state =
      cond do
        Enum.any?(state.pocketed_in_turn, &(&1.number == 8)) ->
          handle_eight_ball_pocketed(state)

        Enum.any?(state.pocketed_in_turn, &(&1.type == :cue)) ->
          %{state | status_message: "Falta! Bola branca na caçapa."} |> switch_turn()

        Enum.empty?(state.pocketed_in_turn) ->
          %{state | status_message: "Nenhuma bola encaçapada."} |> switch_turn()

        true ->
          apply_regular_potting_rules(state)
      end

    Map.put(final_state, :pocketed_in_turn, [])
  end

  @impl SnookerGameEx.Rules
  def get_current_state(state), do: state

  defp apply_regular_potting_rules(state) do
    player = state.current_turn
    pocketed_balls = state.pocketed_in_turn

    case state.game_phase do
      :break ->
        %{
          state
          | game_phase: :open_table,
            status_message: "Mesa aberta! Jogue em qualquer bola (exceto a 8)."
        }

      :open_table ->
        first_potted = List.first(Enum.filter(pocketed_balls, &(&1.type != :cue)))
        assign_suits(state, ball_type_to_suit(first_potted))

      :assigned_suits ->
        player_suit = state.ball_assignments[player]

        {player_balls, opponent_balls} =
          Enum.partition(pocketed_balls, &(ball_type_to_suit(&1) == player_suit))

        if length(player_balls) > 0 and length(opponent_balls) == 0 do
          %{state | status_message: "Boa jogada! Você continua."}
        else
          %{state | status_message: "Falta! Encaçapou bola do oponente."} |> switch_turn()
        end
    end
  end

  defp handle_eight_ball_pocketed(state) do
    player = state.current_turn
    opponent = switch_player_atom(player)
    # TODO: Adicionar lógica real
    player_has_cleared_their_suit? = true

    case state.game_phase do
      :assigned_suits when player_has_cleared_their_suit? ->
        %{
          state
          | winner: player,
            game_phase: :game_over,
            status_message: "Parabéns! Jogador #{player_display(player)} venceu!"
        }

      _ ->
        %{
          state
          | winner: opponent,
            game_phase: :game_over,
            status_message: "Falta grave! Jogador #{player_display(player)} perdeu."
        }
    end
  end

  defp assign_suits(state, potted_suit) do
    player = state.current_turn
    opponent = switch_player_atom(player)
    opponent_suit = if potted_suit == :solid, do: :stripe, else: :solid

    %{
      state
      | game_phase: :assigned_suits,
        ball_assignments: %{player => potted_suit, opponent => opponent_suit},
        status_message: "Naipes definidos! Jogador #{player_display(player)} é #{potted_suit}s."
    }
  end

  defp switch_turn(state),
    do: %{
      state
      | current_turn: switch_player_atom(state.current_turn),
        status_message:
          state.status_message <>
            " Vez do Jogador #{player_display(switch_player_atom(state.current_turn))}."
    }

  defp switch_player_atom(:player1), do: :player2
  defp switch_player_atom(:player2), do: :player1
  defp player_display(:player1), do: "1"
  defp player_display(:player2), do: "2"
  defp ball_type_to_suit(%{type: type}), do: type
end
