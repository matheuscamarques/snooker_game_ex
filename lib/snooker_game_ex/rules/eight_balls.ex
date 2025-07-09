defmodule SnookerGameEx.Rules.EightBall do
  @moduledoc "Implementação das regras do Bola 8."
  @behaviour SnookerGameEx.Rules
  alias SnookerGameEx.Core.GameRules

  # O estado inicial já define `can_shoot: true`, que está correto.
  @impl SnookerGameEx.Rules
  def init(), do: %GameRules{}

  # --- CORREÇÃO PRINCIPAL AQUI ---
  # Trocamos `update_in` pela sintaxe de atualização de struct `%{state | ...}`.
  # Esta é a forma correta de modificar campos em uma struct.
  @impl SnookerGameEx.Rules
  def handle_ball_pocketed(state, ball_data) do
    %{
      state
      | pocketed_in_turn: [ball_data | state.pocketed_in_turn],
        pocketed_balls: [ball_data | state.pocketed_balls]
    }
  end

  @impl SnookerGameEx.Rules
  def handle_turn_end(state) do
    # Se as bolas já estão paradas e é o início do jogo, não fazemos nada.
    # A avaliação só deve ocorrer se não for o estado inicial de quebra.
    # Uma forma simples de verificar isso é se já houve alguma bola encaçapada no turno.
    # No entanto, a lógica mais segura é garantir que a avaliação sempre retorne o estado correto.
    final_state = evaluate_turn(state)
    Map.put(final_state, :pocketed_in_turn, [])
  end

  @impl SnookerGameEx.Rules
  def handle_ball_reposition(state) do
    %{
      state
      | ball_in_hand: false,
        foul_committed: false,
        # O jogador pode atirar após reposicionar
        can_shoot: true,
        status_message: "Bola reposicionada. Jogador #{player_display(state.current_turn)} joga."
    }
  end

  @impl SnookerGameEx.Rules
  def get_current_state(state), do: state

  # --- Lógica de Avaliação do Turno ---

  defp evaluate_turn(state) do
    # Se o jogo acabou, ninguém mais pode atirar.
    if state.winner, do: %{state | can_shoot: false}, else: do_evaluate_turn(state)
  end

  defp do_evaluate_turn(state) do
    _player = state.current_turn
    pocketed_in_turn = state.pocketed_in_turn

    if Enum.any?(pocketed_in_turn, &(&1.number == 8)) do
      handle_eight_ball_pocketed(state)
    else
      {is_foul?, foul_reason} = check_for_foul(state, pocketed_in_turn)

      if is_foul? do
        state
        |> switch_turn()
        |> Map.put(:status_message, "#{foul_reason} Bola na mão para o oponente.")
        |> handle_foul()
      else
        if Enum.empty?(pocketed_in_turn) do
          # Se não for a quebra inicial (break), troca o turno.
          if state.game_phase != :break do
            state
            |> switch_turn()
            |> Map.put(:status_message, "Nenhuma bola encaçapada. Troca de turno.")
          else
            # Mantém o estado como está na quebra inicial se nada foi encaçapado.
            # O jogador pode tentar novamente se a quebra foi inválida (a ser implementado)
            # ou o turno passa. Por agora, mantemos simples.
            %{state | status_message: "Quebra sem bolas encaçapadas. Troca de turno."}
            |> switch_turn()
          end
        else
          apply_regular_potting_rules(state)
        end
      end
    end
  end

  defp handle_foul(state) do
    %{state | foul_committed: true, ball_in_hand: true, can_shoot: true}
  end

  defp check_for_foul(state, pocketed_in_turn) do
    # Não há faltas na quebra inicial
    if state.game_phase == :break,
      do: {false, ""},
      else: do_check_for_foul(state, pocketed_in_turn)
  end

  defp do_check_for_foul(state, pocketed_in_turn) do
    player = state.current_turn

    cond do
      Enum.any?(pocketed_in_turn, &(&1.type == :cue)) ->
        {true, "Falta! Bola branca na caçapa."}

      state.game_phase == :assigned_suits and
          did_pot_opponent_ball?(state, player, pocketed_in_turn) ->
        {true, "Falta! Encaçapou bola do oponente."}

      true ->
        {false, ""}
    end
  end

  defp apply_regular_potting_rules(state) do
    player = state.current_turn

    case state.game_phase do
      :break ->
        %{
          state
          | game_phase: :open_table,
            status_message: "Boa quebra! Mesa aberta. O jogador continua.",
            can_shoot: true
        }

      :open_table ->
        first_potted = List.first(Enum.filter(state.pocketed_in_turn, &(&1.type != :cue)))
        assign_suits(state, ball_type_to_suit(first_potted))

      :assigned_suits ->
        %{
          state
          | status_message: "Boa jogada! Jogador #{player_display(player)} continua.",
            can_shoot: true
        }
    end
  end

  defp handle_eight_ball_pocketed(state) do
    player = state.current_turn
    opponent = switch_player_atom(player)

    # Quando a bola 8 é encaçapada, o jogo termina e ninguém mais pode atirar.
    final_state =
      cond do
        state.game_phase == :assigned_suits and player_has_cleared_their_suit?(state, player) ->
          %{
            state
            | winner: player,
              game_phase: :game_over,
              status_message: "Parabéns! Jogador #{player_display(player)} venceu!"
          }

        true ->
          %{
            state
            | winner: opponent,
              game_phase: :game_over,
              status_message: "Falta grave! Jogador #{player_display(player)} perdeu o jogo."
          }
      end

    %{final_state | can_shoot: false}
  end

  defp assign_suits(state, potted_suit) do
    player = state.current_turn
    opponent = switch_player_atom(player)
    opponent_suit = if potted_suit == :solid, do: :stripe, else: :solid

    %{
      state
      | game_phase: :assigned_suits,
        ball_assignments: %{player => potted_suit, opponent => opponent_suit},
        status_message:
          "Grupos definidos! Jogador #{player_display(player)} é #{potted_suit |> to_string()}. O jogador continua.",
        can_shoot: true
    }
  end

  defp player_has_cleared_their_suit?(state, player) do
    case Map.get(state.ball_assignments, player) do
      nil ->
        false

      player_suit ->
        target_count = 7

        pocketed_count =
          state.pocketed_balls
          |> Enum.filter(&(ball_type_to_suit(&1) == player_suit))
          |> Enum.count()

        pocketed_count == target_count
    end
  end

  defp did_pot_opponent_ball?(state, player, pocketed_in_turn) do
    case Map.get(state.ball_assignments, player) do
      nil ->
        false

      player_suit ->
        opponent_suit = if player_suit == :solid, do: :stripe, else: :solid
        Enum.any?(pocketed_in_turn, &(ball_type_to_suit(&1) == opponent_suit))
    end
  end

  # Garante que ao trocar de turno, o próximo jogador possa atirar.
  defp switch_turn(state),
    do: %{state | current_turn: switch_player_atom(state.current_turn), can_shoot: true}

  defp switch_player_atom(:player1), do: :player2
  defp switch_player_atom(:player2), do: :player1
  defp player_display(:player1), do: "1"
  defp player_display(:player2), do: "2"
  defp ball_type_to_suit(%{type: type}), do: type
end
