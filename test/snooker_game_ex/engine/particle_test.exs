# test/snooker_game_ex/engine/particle_test.exs

defmodule SnookerGameEx.Engine.ParticleTest do
  use ExUnit.Case, async: true

  alias SnookerGameEx.Engine.Particle
  alias SnookerGameEx.Core.GameState
  alias SnookerGameEx.Test.MockNotifier

  # Função auxiliar para iniciar uma partícula com opções padrão e personalizadas.
  defp with_particle(custom_opts, test_function) do
    game_id = "test_game_#{inspect(self())}"
    ets_table = :ets.new(:"ets_#{game_id}", [:set, :public])

    try do
      default_opts = [
        game_id: game_id,
        id: 1,
        ets_table: ets_table,
        notifier: MockNotifier,
        pos: [300.0, 300.0],
        vel: [0.0, 0.0],
        radius: 15.0,
        mass: 1.0,
        color: %{},
        test_pid: self()
      ]

      opts = Keyword.merge(default_opts, custom_opts)
      {:ok, pid} = Particle.start_link(opts)
      context = %{pid: pid, ets_table: ets_table, game_id: game_id, id: opts[:id]}
      test_function.(context)
    after
      :ets.delete(ets_table)
    end
  end

  test "init/1 insere o estado inicial da partícula na tabela ETS" do
    with_particle([pos: [123, 456]], fn context ->
      # CORREÇÃO: Atribui context.id a uma variável local antes do match.
      id = context.id
      assert [{^id, %GameState{pos: [123, 456]}}] = :ets.lookup(context.ets_table, id)
    end)
  end

  test "move/3 atualiza a posição e velocidade da partícula" do
    with_particle([vel: [100.0, 0.0]], fn context ->
      id = context.id
      assert Particle.move(context.game_id, id, 0.016) == :ok
      assert_receive {:particle_update, %GameState{id: ^id, vel: [vx, _vy]} = particle}
      assert vx < 100.0
      assert [{^id, updated_particle}] = :ets.lookup(context.ets_table, id)
      assert updated_particle == particle
    end)
  end

  test "hold/2 para a partícula completamente" do
    with_particle([vel: [100.0, 100.0]], fn context ->
      id = context.id
      assert Particle.hold(context.game_id, id) == :ok
      assert_receive {:particle_update, %GameState{id: ^id, vel: [+0.0, +0.0]}}
    end)
  end

  test "apply_force/3 atualiza a velocidade da partícula" do
    with_particle([vel: [100.0, 0.0]], fn context ->
      id = context.id
      Particle.apply_force(context.game_id, id, {50.0, 50.0})
      assert_receive {:particle_update, %GameState{id: ^id, vel: [150.0, 50.0]}}
    end)
  end

  test "a partícula é removida quando encaçapada" do
    start_pos = [31.0, 31.0]
    velocity_towards_pocket = [-50.0, -50.0]

    with_particle(
      [pos: start_pos, vel: velocity_towards_pocket, color: %{number: 1}],
      fn context ->
        id = context.id
        ref = Process.monitor(context.pid)

        Particle.move(context.game_id, id, 0.016)

        assert_receive {:ball_pocketed, ^id, %{number: 1}}
        assert_receive {:particle_removed, ^id}
        assert_receive {:DOWN, ^ref, :process, _, :normal}
        assert :ets.lookup(context.ets_table, id) == []
      end
    )
  end
end
