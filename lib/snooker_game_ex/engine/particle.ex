defmodule SnookerGameEx.Engine.Particle do
  @moduledoc """
  ADAPTER: Representa uma única partícula (bola) como um GenServer.
  Gerencia o estado individual de uma partícula e usa o Core.Physics para cálculos.
  """
  use GenServer

  alias SnookerGameEx.Core.{GameState, Physics}
  alias SnookerGameEx.Engine.CollisionEngine

  # --- API Pública ---
  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(game_id, id))
  end

  def via_tuple(game_id, id), do: {:via, Registry, {SnookerGameEx.ParticleRegistry, {game_id, id}}}

  def move(game_id, id, dt), do: GenServer.call(via_tuple(game_id, id), {:move, dt})
  def hold(game_id, id), do: GenServer.cast(via_tuple(game_id, id), :hold)
  def apply_force(game_id, id, force), do: GenServer.cast(via_tuple(game_id, id), {:apply_force, force})
  def update_after_collision(game_id, id, vel, pos), do: GenServer.cast(via_tuple(game_id, id), {:update_after_collision, vel, pos})

  # --- Callbacks do GenServer ---
  @impl true
  def init(opts) do
    ets_table = Keyword.fetch!(opts, :ets_table)
    game_id = Keyword.fetch!(opts, :game_id)
    notifier = Keyword.fetch!(opts, :notifier)

    particle_state = %GameState{
      id: Keyword.fetch!(opts, :id),
      pos: Keyword.get(opts, :pos, [0.0, 0.0]),
      vel: Keyword.get(opts, :vel, [0.0, 0.0]),
      radius: Keyword.get(opts, :radius, 10.0),
      mass: Keyword.get(opts, :mass, 1.0),
      color: Keyword.get(opts, :color, %{})
    }

    :ets.insert(ets_table, {particle_state.id, particle_state})

    state = %{
      game_id: game_id,
      ets_table: ets_table,
      notifier: notifier,
      particle: particle_state
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:move, dt}, _from, state) do
    moved_particle =
      Physics.apply_friction_and_move(
        state.particle,
        dt,
        CollisionEngine.friction_coefficient()
      )

    collided_particle = Physics.handle_wall_collision(moved_particle, CollisionEngine.world_bounds())

    pockets = CollisionEngine.pockets()
    pocket_radius = CollisionEngine.pocket_radius()

    if Physics.pocketed?(collided_particle, pockets, pocket_radius) do
      state.notifier.notify_ball_pocketed(
        state.game_id,
        collided_particle.id,
        collided_particle.color
      )
      state.notifier.notify_particle_removed(state.game_id, collided_particle.id)

      :ets.delete(state.ets_table, collided_particle.id)
      {:stop, :normal, :ok, state}
    else
      :ets.insert(state.ets_table, {collided_particle.id, collided_particle})
      state.notifier.notify_particle_update(state.game_id, collided_particle)

      {:reply, :ok, %{state | particle: collided_particle}}
    end
  end

  @impl true
  def handle_cast({:update_after_collision, new_vel, new_pos}, state) do
    updated_particle = %{state.particle | vel: new_vel, pos: new_pos, roll_distance: 0.0}
    :ets.insert(state.ets_table, {updated_particle.id, updated_particle})
    state.notifier.notify_particle_update(state.game_id, updated_particle)
    {:noreply, %{state | particle: updated_particle}}
  end

  @impl true
  def handle_cast(:hold, state) do
    updated_particle = %{state.particle | vel: [0.0, 0.0], roll_distance: 0.0, spin_angle: 0.0}
    :ets.insert(state.ets_table, {updated_particle.id, updated_particle})
    state.notifier.notify_particle_update(state.game_id, updated_particle)
    {:noreply, %{state | particle: updated_particle}}
  end

  # CORREÇÃO: A cláusula agora aceita uma tupla `{fx, fy}` para a força.
  @impl true
  def handle_cast({:apply_force, {fx, fy}}, state) do
    [vx, vy] = state.particle.vel
    mass = state.particle.mass
    new_vel = [vx + fx / mass, vy + fy / mass]
    updated_particle = %{state.particle | vel: new_vel, roll_distance: 0.0, spin_angle: 0.0}
    :ets.insert(state.ets_table, {updated_particle.id, updated_particle})
    state.notifier.notify_particle_update(state.game_id, updated_particle)
    {:noreply, %{state | particle: updated_particle}}
  end
end
