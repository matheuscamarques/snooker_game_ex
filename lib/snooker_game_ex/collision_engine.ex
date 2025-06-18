defmodule SnookerGameEx.CollisionEngine do
  @moduledoc """
  The collision engine that orchestrates the game's physics simulation.
  This version uses a synchronous, in-memory iterative solver to ensure
  rock-solid collision resolution and prevent race conditions.
  """
  use GenServer
  require Logger

  alias SnookerGameEx.Quadtree
  alias SnookerGameEx.Particle
  alias SnookerGameEx.Physics

  @frame_interval_ms 16
  @dt @frame_interval_ms / 1000.0
  @resolution_iterations 10

  @border_width 30.0
  @canvas_width 1000.0
  @canvas_height 500.0
  @particle_radius 15.0
  @particle_mass 1

  @world_bounds %{
    x: @border_width,
    y: @border_width,
    w: @canvas_width - @border_width * 2,
    h: @canvas_height - @border_width * 2
  }

  @quadtree_a :quadtree_a
  @quadtree_b :quadtree_b
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

  # --- API Pública ---
  def pocket_radius, do: @pocket_radius
  def pockets, do: @pockets
  def friction_coefficient, do: 0.3
  def particle_mass, do: @particle_mass
  def particle_radius, do: @particle_radius
  def world_bounds, do: @world_bounds
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # --- Callbacks do GenServer ---
  @impl true
  def init(_opts) do
    Logger.info("Starting Collision Engine with Synchronous Iterative Solver.")
    boundary = world_bounds()
    Quadtree.init(@quadtree_a, boundary, @quadtree_capacity, @quadtree_max_depth)
    Quadtree.init(@quadtree_b, boundary, @quadtree_capacity, @quadtree_max_depth)
    send(self(), :tick)
    {:ok,
     %{
       last_time: System.monotonic_time(),
       accumulator: 0.0,
       active_table: @quadtree_a,
       inactive_table: @quadtree_b
     }}
  end

  @doc """
  Restarts this supervisor
  """
  def restart, do: Supervisor.stop(__MODULE__)

  @impl true
  def handle_info(:tick, state) do
    current_time = System.monotonic_time()
    delta_time_ms =
      (current_time - state.last_time)
      |> System.convert_time_unit(:native, :millisecond)
    capped_delta = min(delta_time_ms / 1000.0, 0.05)
    accumulator = state.accumulator + capped_delta
    new_accumulator = update_simulation_loop(accumulator, state)
    Process.send_after(self(), :tick, @frame_interval_ms)
    {:noreply,
     %{
       state
       | last_time: current_time,
         accumulator: new_accumulator,
         active_table: state.inactive_table,
         inactive_table: state.active_table
     }}
  end

  # --- Lógica do Loop de Simulação ---

  defp update_simulation_loop(accumulator, state) do
    max_steps_per_tick = 1
    simulate_steps(accumulator, max_steps_per_tick, state)
  end

  defp simulate_steps(acc, remaining_steps, state) when acc >= @dt and remaining_steps > 0 do
    broadcast_move_command()
    detect_and_resolve_collisions(state)
    simulate_steps(acc - @dt, remaining_steps - 1, state)
  end

  defp simulate_steps(acc, _, _state), do: acc

  defp broadcast_move_command do
    :particle_data
    |> :ets.tab2list()
    |> Task.async_stream(&GenServer.call(Particle.via_tuple(elem(&1, 0)), {:move, @dt}, 5000))
    |> Stream.run()
  end

  # --- Lógica de Colisão Síncrona ---

  defp detect_and_resolve_collisions(state) do
    all_particles = :ets.tab2list(:particle_data)

    if not Enum.empty?(all_particles) do
      {ids, initial_states} = batch_particles(all_particles)
      final_states =
        iterative_resolution_loop(
          state.inactive_table,
          initial_states,
          @resolution_iterations
        )
      dispatch_final_updates(ids, initial_states, final_states)
    end
  end

  defp iterative_resolution_loop(_table, current_states, 0) do
    current_states
  end

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

  @doc false
  defp dispatch_final_updates(ids, initial_states, final_states) do
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
        GenServer.cast(Particle.via_tuple(particle_id), {:update_after_collision, new_vel, new_pos})
      end
    end
  end

  # --- Funções Auxiliares ---
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
    Enum.with_index(positions_list) |> Enum.each(fn {point, index} -> Quadtree.insert(table, point, index) end)
  end

  defp batch_particles(all_particles) do
    ids = Enum.map(all_particles, &elem(&1, 0))
    pos_idx = Particle.get_attr_index(:pos)
    vel_idx = Particle.get_attr_index(:vel)
    radius_idx = Particle.get_attr_index(:radius)
    mass_idx = Particle.get_attr_index(:mass)
    states = %{
      pos: Enum.map(all_particles, &elem(&1, pos_idx)) |> Nx.tensor(),
      vel: Enum.map(all_particles, &elem(&1, vel_idx)) |> Nx.tensor(),
      # --- CORREÇÃO FINAL DO ERRO DE DIGITAÇÃO ---
      radius:
        Enum.map(all_particles, &elem(&1, radius_idx)) |> Nx.tensor() |> Nx.reshape({:auto, 1}),
      mass: Enum.map(all_particles, &elem(&1, mass_idx)) |> Nx.tensor() |> Nx.reshape({:auto, 1})
    }
    {ids, states}
  end
end
