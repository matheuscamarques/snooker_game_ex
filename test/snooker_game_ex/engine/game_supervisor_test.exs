# test/snooker_game_ex/engine/game_supervisor_test.exs

defmodule SnookerGameEx.Engine.GameSupervisorTest do
  use ExUnit.Case, async: true

  alias SnookerGameEx.Engine.GameSupervisor
  alias SnookerGameEx.Engine.CollisionEngine

  setup do
    game_id = "game_sup_test_#{inspect(self())}"
    # Garante que o jogo não está rodando antes do teste
    GameSupervisor.restart_game(game_id)
    :timer.sleep(50)

    %{game_id: game_id}
  end

  test "start_game/1 inicia uma nova instância de jogo e seus filhos", %{game_id: game_id} do
    assert {:ok, _pid} = GameSupervisor.start_game(game_id)
    assert [{_instance_sup_pid, _}] = Registry.lookup(SnookerGameEx.GameRegistry, game_id)

    assert [{_engine_pid, _}] =
             Registry.lookup(SnookerGameEx.GameRegistry, {CollisionEngine, game_id})

    assert {:ok, :already_started} = GameSupervisor.start_game(game_id)
  end

  test "apply_force/3 envia um cast para o CollisionEngine correto", %{game_id: game_id} do
    {:ok, _pid} = GameSupervisor.start_game(game_id)
    [{engine_pid, _}] = Registry.lookup(SnookerGameEx.GameRegistry, {CollisionEngine, game_id})

    Process.flag(:trap_exit, true)
    ref = Process.monitor(engine_pid)

    assert GameSupervisor.apply_force(game_id, 0, {100, 100}) == :ok
    refute_receive {:DOWN, ^ref, _, _, _}
  end

  test "restart_game/1 termina a instância do jogo", %{game_id: game_id} do
    {:ok, instance_sup_pid} = GameSupervisor.start_game(game_id)

    # CORREÇÃO: Monitora o processo e espera ativamente por sua terminação.
    ref = Process.monitor(instance_sup_pid)

    assert GameSupervisor.restart_game(game_id) == :ok

    # Espera pela mensagem :DOWN, confirmando que o processo morreu.
    assert_receive {:DOWN, ^ref, :process, _, _}

    # Agora que temos certeza que o processo terminou, a verificação do registro é confiável.
    assert [] == Registry.lookup(SnookerGameEx.GameRegistry, game_id)
  end

  test "comandos retornam :game_not_found se o jogo não existe", %{game_id: game_id} do
    assert GameSupervisor.apply_force(game_id, 0, {0, 0}) == {:error, :game_not_found}
    assert GameSupervisor.hold_ball(game_id, 0) == {:error, :game_not_found}
  end
end
