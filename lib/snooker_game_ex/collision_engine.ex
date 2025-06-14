defmodule SnookerGameEx.CollisionEngine do
  @moduledoc """
  The collision engine that orchestrates the game's physics simulation.

  It uses a Quadtree to optimize the detection of collision pairs, which is
  especially efficient for spatially non-uniform data, like clustered snooker balls.
  The engine runs a fixed-step game loop to ensure deterministic physics updates,
  decoupling the simulation from the rendering framerate.
  """
  use GenServer
  require Logger

  # Dependent Modules
  alias SnookerGameEx.Quadtree
  alias SnookerGameEx.Particle
  alias SnookerGameEx.Physics

  # --- Constants ---

  # Simulation timing constants. `@dt` is the fixed timestep for the physics simulation.
  @frame_interval_ms 16
  @dt @frame_interval_ms / 1000.0

  # World and particle dimension constants.
  @border_width 30.0
  @canvas_width 1000.0
  @canvas_height 500.0
  @particle_radius 15.0
  @particle_mass 1

  # Defines the playable area of the snooker table.
  @world_bounds %{
    x: @border_width,
    y: @border_width,
    w: @canvas_width - @border_width * 2,
    h: @canvas_height - @border_width * 2
  }

  # Quadtree configuration constants. These are used for double-buffering.
  @quadtree_a :quadtree_a
  @quadtree_b :quadtree_b
  @quadtree_capacity 4
  @quadtree_max_depth 8

  @pocket_radius 25.0
  @pockets [
    # Cantos
    %{pos: [@border_width, @border_width]},
    %{pos: [@canvas_width - @border_width, @border_width]},
    %{pos: [@border_width, @canvas_height - @border_width]},
    %{pos: [@canvas_width - @border_width, @canvas_height - @border_width]},
    # Meios
    %{pos: [@canvas_width / 2, @border_width]},
    %{pos: [@canvas_width / 2, @canvas_height - @border_width]}
  ]

  @doc "Returns the radius of the pockets."
  @spec pocket_radius() :: float()
  def pocket_radius, do: @pocket_radius

  @doc "Returns a list of pocket positions."
  @spec pockets() :: list(map())
  def pockets, do: @pockets

  @friction_coefficient 0.3
  @spec friction_coefficient() :: float()
  def friction_coefficient, do: @friction_coefficient

  @doc "Returns the default mass for a particle."
  @spec particle_mass() :: integer()
  def particle_mass, do: @particle_mass

  # --- Public API ---

  @doc "Returns the default mass for a particle."
  @spec particle_mass() :: integer()
  def particle_mass, do: @particle_mass

  @doc "Returns the default radius for a particle."
  @spec particle_radius() :: float()
  def particle_radius, do: @particle_radius

  @doc "Returns the world boundaries in the format expected by the Quadtree."
  @spec world_bounds() :: %{x: float(), y: float(), w: float(), h: float()}
  def world_bounds, do: @world_bounds

  @doc "Starts the CollisionEngine GenServer."
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting Collision Engine with Quadtree...")

    # Initialize two separate Quadtrees. This is a "double-buffering" technique.
    # While one tree is being read for collision checks (the active one), the other
    # (the inactive one) is being cleared and rebuilt with the next frame's data.
    boundary = world_bounds()
    Quadtree.init(@quadtree_a, boundary, @quadtree_capacity, @quadtree_max_depth)
    Quadtree.init(@quadtree_b, boundary, @quadtree_capacity, @quadtree_max_depth)

    # Start the simulation's internal clock.
    send(self(), :tick)

    initial_state = %{
      last_time: System.monotonic_time(),
      accumulator: 0.0,
      active_table: @quadtree_a,
      inactive_table: @quadtree_b
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_info(:tick, state) do
    current_time = System.monotonic_time()

    # Calculate the real time that has passed since the last tick.
    delta_time_ms =
      (current_time - state.last_time)
      |> System.convert_time_unit(:native, :millisecond)

    # Cap the delta time to prevent a "spiral of death" where a lag spike
    # causes the simulation to try to compute too many steps at once, causing more lag.
    capped_delta = min(delta_time_ms / 1000.0, 0.05)

    # Add the elapsed time to an accumulator.
    accumulator = state.accumulator + capped_delta
    # Run the fixed-step simulation, which will consume the accumulated time.
    new_accumulator = update_simulation_loop(accumulator, state)

    # Schedule the next tick.
    Process.send_after(self(), :tick, @frame_interval_ms)

    # Swap the active and inactive Quadtree tables for the next frame.
    new_state = %{
      state
      | last_time: current_time,
        accumulator: new_accumulator,
        active_table: state.inactive_table,
        inactive_table: state.active_table
    }

    {:noreply, new_state}
  end

  # --- Simulation Loop Logic ---
  # These functions are public to allow for detailed documentation as requested,
  # but they are designed for internal use by the simulation loop.

  @doc """
  Runs the simulation in fixed time steps.

  This is the entry point for the fixed-step loop. It consumes the accumulated
  time by running `simulate_steps/3` as many times as needed.
  """
  @spec update_simulation_loop(accumulator :: float(), state :: map()) :: float()
  def update_simulation_loop(accumulator, state) do
    # To prevent extreme lag, limit the number of simulation steps per visual frame.
    max_steps_per_tick = 1
    simulate_steps(accumulator, max_steps_per_tick, state)
  end

  @doc """
  Recursively executes a single, fixed-time step of the simulation.

  Each step involves:
  1. Broadcasting a command for all particles to move.
  2. Detecting and resolving collisions for that step.

  It continues until the time accumulator is less than the fixed step time (`@dt`)
  or the maximum number of steps per frame is reached.
  """
  @spec simulate_steps(acc :: float(), remaining_steps :: integer(), state :: map()) :: float()
  def simulate_steps(acc, remaining_steps, state) when acc >= @dt and remaining_steps > 0 do
    broadcast_move_command()
    detect_and_notify_collisions(state)
    simulate_steps(acc - @dt, remaining_steps - 1, state)
  end

  def simulate_steps(acc, _, _state), do: acc

  @doc """
  Broadcasts a `move` command to all active `Particle` processes.

  It reads all particle data from the shared ETS table and sends a synchronous
  `GenServer.call` to each particle, telling it to update its position based
  on its velocity and the fixed time step `@dt`.
  """
  @spec broadcast_move_command() :: :ok
  def broadcast_move_command do
    :particle_data
    |> :ets.tab2list()
    |> Task.async_stream(
      fn particle_tuple ->
        id = elem(particle_tuple, Particle.get_attr_index(:id))
        GenServer.call(Particle.via_tuple(id), {:move, @dt}, 5000)
      end,
      timeout: 6000,
      max_concurrency: System.schedulers_online()
    )
    |> Stream.run()

    :ok
  end

  def handle_info(massage, state) do
    {:noreply, state}
  end

  @doc """
  The main pipeline for collision detection and response.

  This function orchestrates the entire collision check for a single simulation step.
  It performs the following actions:
  1. Fetches all particle states from ETS.
  2. Batches the states into `Nx` tensors for efficient processing.
  3. Builds a spatial partitioning structure (Quadtree) for the current frame.
  4. Queries the Quadtree to find potential collision pairs (broad phase).
  5. Uses `Physics.get_colliding_pairs/2` to precisely check for actual collisions (narrow phase).
  6. If collisions exist, it calculates the physical responses (new velocities and positions).
  7. Dispatches the updates to the corresponding `Particle` processes.
  """
  @spec detect_and_notify_collisions(state :: map()) :: :ok
  def detect_and_notify_collisions(state) do
    all_particles = :ets.tab2list(:particle_data)

    if Enum.empty?(all_particles) do
      :ok
    else
      {ids, initial_states} = batch_particles(all_particles)

      # Build the Quadtree for this frame in the *inactive* table.
      build_spatial_structure(state.inactive_table, initial_states)

      # Find pairs of particles that might be colliding.
      candidate_pairs = find_candidate_pairs(state.inactive_table, initial_states)

      if Enum.any?(candidate_pairs) do
        candidate_tensor = Nx.tensor(candidate_pairs)
        # Narrow phase: filter candidates to find actual collisions.
        colliding_pairs_tensor = Physics.get_colliding_pairs(initial_states, candidate_tensor)

        # If there are any collisions, calculate and dispatch the responses.
        if Nx.axis_size(colliding_pairs_tensor, 0) > 0 do
          collision_updates =
            Physics.calculate_collision_responses(initial_states, colliding_pairs_tensor)

          dispatch_collision_updates(ids, collision_updates)
        end
      end

      :ok
    end
  end

  @doc """
  Finds candidate collision pairs using the Quadtree (Broad Phase).

  For each particle, it queries the Quadtree to find other particles in its
  vicinity. This significantly reduces the number of pairs that need to be
  checked in the more expensive narrow phase, from O(n^2) to O(n log n) on average.
  The process is parallelized using `Task.async_stream` for performance.
  """
  @spec find_candidate_pairs(Quadtree.table_name(), Physics.batch_states()) :: list([integer()])
  def find_candidate_pairs(table, states) do
    num_particles_in_frame = Nx.axis_size(states.pos, 0)
    positions_list = Nx.to_list(states.pos)
    radii_list = Nx.to_list(states.radius)

    0..(num_particles_in_frame - 1)
    |> Task.async_stream(
      fn index ->
        [px, py] = Enum.at(positions_list, index)
        [r] = Enum.at(radii_list, index)

        # Create a bounding box around the particle.
        # Any particle whose center is within this box is a candidate.
        query_range = %{x: px - r, y: py - r, w: r * 2, h: r * 2}

        Quadtree.query(table, query_range)
        # Avoid duplicate pairs (i,j) vs (j,i) and self-collision (i,i).
        |> Enum.filter(&(&1 > index))
        |> Enum.map(&[index, &1])
      end,
      max_concurrency: System.schedulers_online() * 2,
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, pairs} -> pairs end)
  end

  @doc """
  Builds the spatial data structure (Quadtree) for the current frame.

  It first clears the Quadtree to remove data from the previous frame,
  then iterates through all particles and inserts their current positions
  and indices into the tree.
  """
  @spec build_spatial_structure(Quadtree.table_name(), Physics.batch_states()) :: :ok
  def build_spatial_structure(table, states) do
    Quadtree.clear(table)
    positions_list = Nx.to_list(states.pos)

    Enum.with_index(positions_list)
    |> Enum.each(fn {point, index} ->
      Quadtree.insert(table, point, index)
    end)
  end

  @doc """
  Dispatches collision updates to the relevant `Particle` processes.

  After the physics calculations are complete, this function takes the results
  (new velocities and positions) and sends them as `GenServer.cast` messages
  to the two particles involved in each collision.
  """
  @spec dispatch_collision_updates(list(any()), list(map())) :: :ok
  def dispatch_collision_updates(ids, collision_updates) do
    ids_tuple = List.to_tuple(ids)

    collision_updates
    |> Enum.each(fn result ->
      # Look up the actual particle IDs from the temporary indices used in this frame.
      particle_id_a = elem(ids_tuple, result.index_a)
      particle_id_b = elem(ids_tuple, result.index_b)

      # Cast the updates to the respective particle processes.
      GenServer.cast(
        Particle.via_tuple(particle_id_a),
        {:update_after_collision, result.new_vel_a, result.new_pos_a}
      )

      GenServer.cast(
        Particle.via_tuple(particle_id_b),
        {:update_after_collision, result.new_vel_b, result.new_pos_b}
      )
    end)
  end

  @doc """
  Batches particle data from a list of tuples into `Nx` tensors.

  This is a data transformation step that prepares the raw particle data from
  ETS for efficient, vectorized computation in the `SnookerGameEx.Physics` module.
  """
  @spec batch_particles(list(tuple())) :: {list(any()), Physics.batch_states()}
  def batch_particles(all_particles) do
    ids = Enum.map(all_particles, &elem(&1, 0))
    pos_idx = Particle.get_attr_index(:pos)
    vel_idx = Particle.get_attr_index(:vel)
    radius_idx = Particle.get_attr_index(:radius)
    mass_idx = Particle.get_attr_index(:mass)

    states = %{
      pos: Enum.map(all_particles, &elem(&1, pos_idx)) |> Nx.tensor(),
      vel: Enum.map(all_particles, &elem(&1, vel_idx)) |> Nx.tensor(),
      radius:
        Enum.map(all_particles, &elem(&1, radius_idx)) |> Nx.tensor() |> Nx.reshape({:auto, 1}),
      mass: Enum.map(all_particles, &elem(&1, mass_idx)) |> Nx.tensor() |> Nx.reshape({:auto, 1})
    }

    {ids, states}
  end
end
