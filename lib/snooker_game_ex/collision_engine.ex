defmodule SnookerGameEx.CollisionEngine do
  @moduledoc """
  Motor de colisão que orquestra a simulação do jogo.
  Utiliza uma Quadtree para otimizar a detecção de pares de colisão,
  o que é especialmente eficiente para dados espacialmente não uniformes,
  como bolas de sinuca agrupadas.
  """
  use GenServer
  require Logger

  # Módulos dependentes
  alias SnookerGameEx.Quadtree
  alias SnookerGameEx.Particle
  alias SnookerGameEx.Physics

  # Constantes da simulação
  @frame_interval_ms 16
  @dt @frame_interval_ms / 1000.0
  @border_width 30.0
  @canvas_width 1000.0
  @canvas_height 500.0

  @world_bounds %{
    x: @border_width,
    y: @border_width,
    w: @canvas_width - @border_width * 2,
    h: @canvas_height - @border_width * 2
  }
  @particle_radius 15.0
  @particle_mass 1

  # Constantes para a Quadtree
  @quadtree_a :quadtree_a
  @quadtree_b :quadtree_b
  @quadtree_capacity 4
  @quadtree_max_depth 8

  # --- API Pública ---

  @doc "Retorna a massa padrão de uma partícula."
  def particle_mass, do: @particle_mass

  @doc "Retorna o raio padrão de uma partícula."
  def particle_radius, do: @particle_radius

  @doc "Retorna os limites do mundo no formato esperado pela Quadtree."
  def world_bounds, do: @world_bounds

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Callbacks do GenServer ---

  @impl true
  def init(_opts) do
    Logger.info("Iniciando o Motor de Colisão com Quadtree...")

    # Inicializa as duas Quadtrees para o double-buffering.
    boundary = world_bounds()
    Quadtree.init(@quadtree_a, boundary, @quadtree_capacity, @quadtree_max_depth)
    Quadtree.init(@quadtree_b, boundary, @quadtree_capacity, @quadtree_max_depth)

    # Inicia o loop da simulação.
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

    delta_time_ms =
      (current_time - state.last_time)
      |> System.convert_time_unit(:native, :millisecond)

    # Limita o delta time para evitar "espiral da morte" em caso de lag.
    capped_delta = min(delta_time_ms / 1000.0, 0.05)

    accumulator = state.accumulator + capped_delta
    new_accumulator = update_simulation_loop(accumulator, state)

    Process.send_after(self(), :tick, @frame_interval_ms)

    # Troca as tabelas (double buffering) para o próximo frame.
    new_state = %{
      state
      | last_time: current_time,
        accumulator: new_accumulator,
        active_table: state.inactive_table,
        inactive_table: state.active_table
    }

    {:noreply, new_state}
  end

  # --- Lógica do Loop de Simulação ---

  defp update_simulation_loop(accumulator, state) do
    # Executa a simulação em passos de tempo fixos.
    max_steps_per_tick = 5
    simulate_steps(accumulator, max_steps_per_tick, state)
  end

  defp simulate_steps(acc, remaining_steps, state) when acc >= @dt and remaining_steps > 0 do
    broadcast_move_command()
    detect_and_notify_collisions(state)
    simulate_steps(acc - @dt, remaining_steps - 1, state)
  end

  defp simulate_steps(acc, _, _state), do: acc

  defp broadcast_move_command do
    :particle_data
    |> :ets.tab2list()
    |> Enum.each(fn particle_tuple ->
      id = elem(particle_tuple, Particle.get_attr_index(:id))
      GenServer.call(Particle.via_tuple(id), {:move, @dt}, 5000)
    end)
  end

  defp detect_and_notify_collisions(state) do
    all_particles = :ets.tab2list(:particle_data)

    if Enum.empty?(all_particles) do
      :ok
    else
      {ids, initial_states} = batch_particles(all_particles)

      # Constrói a Quadtree para este frame na tabela inativa.
      build_spatial_structure(state.inactive_table, initial_states)

      # Encontra pares de partículas que podem colidir.
      candidate_pairs = find_candidate_pairs(state.inactive_table, initial_states)

      if Enum.any?(candidate_pairs) do
        candidate_tensor = Nx.tensor(candidate_pairs)
        colliding_pairs_tensor = Physics.get_colliding_pairs(initial_states, candidate_tensor)

        if Nx.axis_size(colliding_pairs_tensor, 0) > 0 do
          collision_updates =
            Physics.calculate_collision_responses(initial_states, colliding_pairs_tensor)

          dispatch_collision_updates(ids, collision_updates)
        end
      end
    end
  end

  defp find_candidate_pairs(table, states) do
    num_particles_in_frame = Nx.axis_size(states.pos, 0)
    positions_list = Nx.to_list(states.pos)
    radii_list = Nx.to_list(states.radius)

    0..(num_particles_in_frame - 1)
    |> Task.async_stream(
      fn index ->
        [px, py] = Enum.at(positions_list, index)
        [r] = Enum.at(radii_list, index)

        # Cria uma caixa de busca ao redor da partícula.
        # Qualquer partícula cujo centro esteja nesta caixa é uma candidata.
        query_range = %{x: px - r, y: py - r, w: r * 2, h: r * 2}

        Quadtree.query(table, query_range)
        # Evita pares duplicados e auto-colisão.
        |> Enum.filter(&(&1 > index))
        |> Enum.map(&[index, &1])
      end,
      max_concurrency: System.schedulers_online() * 2,
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, pairs} -> pairs end)
  end

  defp build_spatial_structure(table, states) do
    # Limpa a Quadtree e a reconstrói com as posições atuais.
    Quadtree.clear(table)
    positions_list = Nx.to_list(states.pos)

    Enum.with_index(positions_list)
    |> Enum.each(fn {point, index} ->
      Quadtree.insert(table, point, index)
    end)
  end

  defp dispatch_collision_updates(ids, collision_updates) do
    ids_tuple = List.to_tuple(ids)

    collision_updates
    |> Enum.each(fn result ->
      particle_id_a = elem(ids_tuple, result.index_a)
      particle_id_b = elem(ids_tuple, result.index_b)

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

  # --- Funções Auxiliares de Dados ---

  defp batch_particles(all_particles) do
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
