defmodule SnookerGameEx.Engine.CollisionEngine do
  @moduledoc """
  ADAPTER: O motor de simulação principal.
  Implementa o behaviour `SnookerGameEx.Game` e orquestra a simulação.
  É um GenServer que gerencia o loop do jogo e o estado das partículas.
  """
  use GenServer
  require Logger

  alias SnookerGameEx.Engine.{Particle, Quadtree}
  alias SnookerGameEx.Core.Physics

  # --- Constantes de Simulação ---
  @frame_interval_ms 16
  @dt @frame_interval_ms / 1000.0
  @resolution_iterations 10
  @border_width 30.0
  @canvas_width 1000.0
  @canvas_height 500.0
  @particle_radius 15.0
  @particle_mass 1
  @friction_coefficient 0.3
  @world_bounds %{
    x: @border_width,
    y: @border_width,
    w: @canvas_width - @border_width * 2,
    h: @canvas_height - @border_width * 2
  }
  @quadtree_capacity 4
  @quadtree_max_depth 8
  @pocket_radius 25.0
  @pockets [
    %{pos: [@border_width, @border_width]},
    %{pos: [@canvas_width - @border_width, @border_width]},
    %{pos: [@border_width, @canvas_height - @border_width]},
    %{pos: [@canvas_width - @border_width, @canvas_height - @border_width]},
    %{pos: [@canvas_width / 2, @border_width]},
    %{pos: [@canvas_width / 2, @canvas_height - @border_width]}
  ]

  # --- API Pública (para constantes) ---
  def pocket_radius, do: @pocket_radius
  def pockets, do: @pockets
  def friction_coefficient, do: @friction_coefficient
  def particle_mass, do: @particle_mass
  def particle_radius, do: @particle_radius
  def world_bounds, do: @world_bounds

  # --- Início do GenServer ---
  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    notifier = Keyword.get(opts, :notifier, SnookerGameEx.Notifiers.PubSubNotifier)
    state = [game_id: game_id, notifier: notifier] ++ opts
    GenServer.start_link(__MODULE__, state, name: via_tuple(game_id))
  end

  def via_tuple(game_id),
    do: {:via, Registry, {SnookerGameEx.GameRegistry, {__MODULE__, game_id}}}

  # --- Callbacks do GenServer ---
  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    ets_table = Keyword.fetch!(opts, :ets_table)
    notifier = Keyword.fetch!(opts, :notifier)
    Logger.info("[Game #{game_id}] Starting Collision Engine")

    quadtree_a_tid = :ets.new(:"#{game_id}_quad_a", [:set, :public, read_concurrency: true])
    quadtree_b_tid = :ets.new(:"#{game_id}_quad_b", [:set, :public, read_concurrency: true])

    boundary = world_bounds()
    Quadtree.initialize(quadtree_a_tid, boundary, @quadtree_capacity, @quadtree_max_depth)
    Quadtree.initialize(quadtree_b_tid, boundary, @quadtree_capacity, @quadtree_max_depth)

    send(self(), :tick)

    {:ok,
     %{
       game_id: game_id,
       ets_table: ets_table,
       notifier: notifier,
       last_time: System.monotonic_time(),
       accumulator: 0.0,
       active_table: quadtree_a_tid,
       inactive_table: quadtree_b_tid,
       balls_are_moving: false
     }}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "[Game #{state.game_id}] Terminating Collision Engine. Reason: #{inspect(reason)}"
    )

    :ets.delete(state.active_table)
    :ets.delete(state.inactive_table)
    :ok
  end

  @impl true
  def handle_cast({:apply_force, particle_id, force}, state) do
    Logger.debug("[Game #{state.game_id}] Applying force to particle #{particle_id}")
    Particle.apply_force(state.game_id, particle_id, force)
    {:noreply, %{state | balls_are_moving: true}}
  end

  @impl true
  def handle_cast({:hold_ball, particle_id}, state) do
    Particle.hold(state.game_id, particle_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    current_time = System.monotonic_time()

    delta_time_ms =
      System.convert_time_unit(current_time - state.last_time, :native, :millisecond)

    capped_delta = min(delta_time_ms / 1000.0, 0.05)
    accumulator = state.accumulator + capped_delta

    new_accumulator = update_simulation_loop(accumulator, state)

    previously_moving = state.balls_are_moving
    currently_moving = are_any_balls_moving?(state.ets_table, state.game_id)

    if previously_moving and not currently_moving do
      Logger.info("[Game #{state.game_id}] All balls stopped. Notifying GameLogic.")
      state.notifier.notify_all_balls_stopped(state.game_id)
    end

    Process.send_after(self(), :tick, @frame_interval_ms)

    {:noreply,
     %{
       state
       | last_time: current_time,
         accumulator: new_accumulator,
         active_table: state.inactive_table,
         inactive_table: state.active_table,
         balls_are_moving: currently_moving
     }}
  end

  defp are_any_balls_moving?(ets_table, _game_id) do
    is_moving =
      ets_table
      |> :ets.tab2list()
      |> Enum.any?(fn {_id, particle_state} ->
        [vx, vy] = particle_state.vel
        magnitude_sq = vx * vx + vy * vy
        magnitude_sq > 0.01
      end)

    is_moving
  end

  defp update_simulation_loop(accumulator, state) do
    max_steps_per_tick = 1
    simulate_steps(accumulator, max_steps_per_tick, state)
  end

  defp simulate_steps(acc, 0, _state), do: acc

  defp simulate_steps(acc, remaining_steps, state) when acc >= @dt do
    broadcast_move_command(state.game_id, state.ets_table)
    detect_and_resolve_collisions(state)
    simulate_steps(acc - @dt, remaining_steps - 1, state)
  end

  defp simulate_steps(acc, _, _state), do: acc

  defp broadcast_move_command(game_id, ets_table) do
    ets_table
    |> :ets.tab2list()
    |> Task.async_stream(fn {particle_id, _particle_data} ->
      Particle.move(game_id, particle_id, @dt)
    end)
    |> Stream.run()
  end

  defp detect_and_resolve_collisions(state) do
    all_particles = :ets.tab2list(state.ets_table)

    if not Enum.empty?(all_particles) do
      {ids, initial_states} = batch_particles(all_particles)

      final_states =
        iterative_resolution_loop(
          state.inactive_table,
          initial_states,
          @resolution_iterations
        )

      dispatch_final_updates(state.game_id, ids, initial_states, final_states)
    end
  end

  defp iterative_resolution_loop(_table, current_states, 0), do: current_states

  defp iterative_resolution_loop(table, current_states, iterations_left) do
    build_spatial_structure(table, current_states)
    candidate_pairs = find_candidate_pairs(table, current_states)

    if Enum.empty?(candidate_pairs) do
      current_states
    else
      candidate_tensor = Nx.tensor(candidate_pairs)
      colliding_pairs_tensor = Physics.get_colliding_pairs(current_states, candidate_tensor)

      if Nx.axis_size(colliding_pairs_tensor, 0) > 0 do
        collision_results =
          Physics.calculate_collision_responses(current_states, colliding_pairs_tensor)

        updated_states = Physics.apply_collision_updates(current_states, collision_results)
        iterative_resolution_loop(table, updated_states, iterations_left - 1)
      else
        current_states
      end
    end
  end

  defp dispatch_final_updates(game_id, ids, initial_states, final_states) do
    pos_diff = Nx.abs(Nx.subtract(initial_states.pos, final_states.pos))
    max_diff_per_particle = Nx.reduce_max(pos_diff, axes: [1])
    changed_mask = Nx.greater(max_diff_per_particle, 1.0e-6)

    changed_indices_list =
      changed_mask
      |> Nx.to_list()
      |> Enum.with_index()
      |> Enum.filter(fn {value, _index} -> value == 1 end)
      |> Enum.map(fn {_value, index} -> index end)

    if not Enum.empty?(changed_indices_list) do
      ids_tuple = List.to_tuple(ids)
      final_pos_list = Nx.to_list(final_states.pos)
      final_vel_list = Nx.to_list(final_states.vel)

      for index <- changed_indices_list do
        particle_id = elem(ids_tuple, index)
        new_pos = Enum.at(final_pos_list, index)
        new_vel = Enum.at(final_vel_list, index)

        Particle.update_after_collision(game_id, particle_id, new_vel, new_pos)
      end
    end
  end

  defp find_candidate_pairs(table, states) do
    num_particles = Nx.axis_size(states.pos, 0)
    positions_list = Nx.to_list(states.pos)
    radii_list = Nx.to_list(states.radius)

    0..(num_particles - 1)
    |> Task.async_stream(
      fn index ->
        [px, py] = Enum.at(positions_list, index)
        [r] = Enum.at(radii_list, index)
        query_range = %{x: px - r, y: py - r, w: r * 2, h: r * 2}
        Quadtree.query(table, query_range) |> Enum.filter(&(&1 > index)) |> Enum.map(&[index, &1])
      end,
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, pairs} -> pairs end)
  end

  defp build_spatial_structure(table, states) do
    Quadtree.clear(table)
    positions_list = Nx.to_list(states.pos)

    Enum.with_index(positions_list)
    |> Enum.each(fn {point, index} -> Quadtree.insert(table, point, index) end)
  end

  defp batch_particles(all_particles) do
    ids = Enum.map(all_particles, &elem(&1, 0))

    pos_list = Enum.map(all_particles, &elem(&1, 1).pos)
    vel_list = Enum.map(all_particles, &elem(&1, 1).vel)
    radius_list = Enum.map(all_particles, &elem(&1, 1).radius)
    mass_list = Enum.map(all_particles, &elem(&1, 1).mass)

    states = %{
      pos: Nx.tensor(pos_list),
      vel: Nx.tensor(vel_list),
      radius: Nx.tensor(radius_list) |> Nx.reshape({:auto, 1}),
      mass: Nx.tensor(mass_list) |> Nx.reshape({:auto, 1})
    }

    {ids, states}
  end
end
