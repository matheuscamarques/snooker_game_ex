defmodule SnookerGameEx.Particle do
  @moduledoc """
  Representa uma única partícula (uma bola) na simulação de um jogo específico.
  """
  use GenServer

  alias SnookerGameEx.Physics
  alias SnookerGameEx.CollisionEngine

  @simulation_topic "particle_updates"
  @game_events_topic "game_events"

  @typedoc "O estado do GenServer armazena os dados do jogo e da partícula."
  @type state :: {game_id :: String.t(), ets_table :: atom(), particle_data :: particle_tuple()}

  @typedoc "A tupla que representa os dados brutos de uma partícula."
  @type particle_tuple ::
          {id :: any(), pos :: list(float()), vel :: list(float()), radius :: float(),
           mass :: float(), color :: map(), spin_angle :: float(), roll_distance :: float()}

  @doc "Inicia um GenServer de partícula para um jogo específico."
  @spec start_link(list) :: GenServer.on_start()
  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(game_id, id))
  end

  def via_tuple(game_id, id),
    do: {:via, Registry, {SnookerGameEx.ParticleRegistry, {game_id, id}}}

  @impl true
  def init(opts) do
    ets_table = Keyword.fetch!(opts, :ets_table)
    game_id = Keyword.fetch!(opts, :game_id)

    particle_tuple =
      {
        Keyword.fetch!(opts, :id),
        Keyword.get(opts, :pos, [0.0, 0.0]),
        Keyword.get(opts, :vel, [0.0, 0.0]),
        Keyword.get(opts, :radius, 10.0),
        Keyword.get(opts, :mass, 1.0),
        Keyword.get(opts, :color, %{}),
        # spin_angle
        0.0,
        # roll_distance
        0.0
      }

    # CORREÇÃO: Usando a variável `ets_table` correta.
    :ets.insert(ets_table, particle_tuple)

    # CORREÇÃO: Usando a variável `particle_tuple` correta e definindo o estado inicial do GenServer.
    state = {game_id, ets_table, particle_tuple}
    {:ok, state}
  end

  @impl true
  def handle_call({:move, dt}, _from, {game_id, ets_table, current_data} = state) do
    if Physics.velocity_magnitude(elem(current_data, get_attr_index(:vel))) < 0.01 do
      new_data = put_elem(current_data, get_attr_index(:vel), [0.0, 0.0])

      # CORREÇÃO: Usando `ets_table` e passando `game_id` para o broadcast.
      :ets.insert(ets_table, new_data)
      broadcast_update(game_id, new_data)

      # CORREÇÃO: Retornando a estrutura de estado completa e correta.
      new_state = {game_id, ets_table, new_data}
      {:reply, :ok, new_state}
    else
      bounds = CollisionEngine.world_bounds()
      {id, pos, vel, radius, _mass, color, current_spin, current_roll} = current_data

      friction = CollisionEngine.friction_coefficient()
      [vx, vy] = vel
      damping_factor = :math.pow(1.0 - friction, dt)
      damped_vel = [vx * damping_factor, vy * damping_factor]

      distance_moved = Physics.velocity_magnitude(damped_vel) * dt
      new_roll_distance = current_roll + distance_moved
      new_spin_angle = current_spin + distance_moved / radius * 0.01

      [px, py] = pos
      [dvx, dvy] = damped_vel
      new_pos_integrated = [px + dvx * dt, py + dvy * dt]

      {final_pos, final_vel} =
        Physics.handle_wall_collision(
          %{pos: new_pos_integrated, vel: damped_vel, radius: radius},
          bounds
        )

      pockets = CollisionEngine.pockets()
      pocket_radius = CollisionEngine.pocket_radius()

      if Physics.pocketed?(final_pos, pockets, pocket_radius) do
        Phoenix.PubSub.broadcast(
          SnookerGameEx.PubSub,
          "#{@game_events_topic}:#{game_id}",
          {:ball_pocketed, id, color}
        )

        :ets.delete(ets_table, id)
        {:stop, :normal, :ok, state}
      else
        new_data =
          current_data
          |> put_elem(get_attr_index(:pos), final_pos)
          |> put_elem(get_attr_index(:vel), final_vel)
          |> put_elem(get_attr_index(:spin_angle), new_spin_angle)
          |> put_elem(get_attr_index(:roll_distance), new_roll_distance)

        # CORREÇÃO: Usando a variável `new_data` correta.
        :ets.insert(ets_table, new_data)
        broadcast_update(game_id, new_data)

        # CORREÇÃO: Retornando a estrutura de estado completa e correta.
        new_state = {game_id, ets_table, new_data}
        {:reply, :ok, new_state}
      end
    end
  end

  # CORREÇÃO: Todos os handle_cast foram atualizados para usar a estrutura de estado correta.
  @impl true
  def handle_cast(
        {:update_after_collision, new_velocity, new_position},
        {game_id, ets_table, current_data}
      ) do
    new_data =
      current_data
      |> put_elem(get_attr_index(:vel), new_velocity)
      |> put_elem(get_attr_index(:pos), new_position)
      |> put_elem(get_attr_index(:roll_distance), 0.0)

    :ets.insert(ets_table, new_data)
    broadcast_update(game_id, new_data)

    new_state = {game_id, ets_table, new_data}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:hold, {game_id, ets_table, current_data}) do
    new_data =
      current_data
      |> put_elem(get_attr_index(:vel), [0.0, 0.0])
      |> put_elem(get_attr_index(:spin_angle), 0.0)
      |> put_elem(get_attr_index(:roll_distance), 0.0)

    :ets.insert(ets_table, new_data)
    # Não há necessidade de broadcast para 'hold', mas a atualização do ETS é mantida.

    new_state = {game_id, ets_table, new_data}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:apply_force, [fx, fy]}, {game_id, ets_table, current_data}) do
    {_id, _pos, [vx, vy], _radius, mass, _color, _spin, _roll} = current_data
    new_velocity = [vx + fx / mass, vy + fy / mass]

    new_data =
      current_data
      |> put_elem(get_attr_index(:vel), new_velocity)
      |> put_elem(get_attr_index(:spin_angle), 0.0)
      |> put_elem(get_attr_index(:roll_distance), 0.0)

    :ets.insert(ets_table, new_data)

    # O broadcast ocorrerá naturalmente no próximo tick de :move, então não é estritamente necessário aqui.
    # Mas podemos adicioná-lo para uma resposta mais imediata.
    broadcast_update(game_id, new_data)

    new_state = {game_id, ets_table, new_data}
    {:noreply, new_state}
  end

  @spec broadcast_update(String.t(), particle_tuple()) :: :ok
  def broadcast_update(game_id, particle_tuple) do
    payload = %{
      id: elem(particle_tuple, get_attr_index(:id)),
      pos: elem(particle_tuple, get_attr_index(:pos)),
      vel: elem(particle_tuple, get_attr_index(:vel)),
      radius: elem(particle_tuple, get_attr_index(:radius)),
      color: elem(particle_tuple, get_attr_index(:color)),
      spin_angle: elem(particle_tuple, get_attr_index(:spin_angle)),
      roll_distance: elem(particle_tuple, get_attr_index(:roll_distance))
    }

    Phoenix.PubSub.broadcast(
      SnookerGameEx.PubSub,
      "#{@simulation_topic}:#{game_id}",
      {:particle_moved, payload}
    )
  end

  @spec get_attr_index(atom()) :: non_neg_integer()
  def get_attr_index(attr) do
    case attr do
      :id -> 0
      :pos -> 1
      :vel -> 2
      :radius -> 3
      :mass -> 4
      :color -> 5
      :spin_angle -> 6
      :roll_distance -> 7
      _ -> raise ArgumentError, "Unknown attribute: #{inspect(attr)}"
    end
  end
end
