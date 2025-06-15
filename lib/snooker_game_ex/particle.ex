defmodule SnookerGameEx.Particle do
  @moduledoc """
  Represents a single particle (a ball) in the simulation.
  """
  use GenServer

  alias SnookerGameEx.Physics
  alias SnookerGameEx.CollisionEngine

  @game_events_topic "game_events"
  @simulation_topic "particle_updates"

  @typedoc "The particle state now tracks spin and roll independently."
  @type particle_state ::
          {id :: any(), pos :: list(float()), vel :: list(float()), radius :: float(),
           mass :: float(), color :: map(), spin_angle :: float(), roll_distance :: float()}

  @doc "Starts a particle GenServer."
  @spec start_link(list) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def via_tuple(id), do: {:via, Registry, {SnookerGameEx.ParticleRegistry, id}}

  @impl true
  def init(opts) do
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

    :ets.insert(:particle_data, particle_tuple)
    {:ok, particle_tuple}
  end

  @impl true
  def handle_call({:move, dt}, _from, current_state) do
    if Physics.velocity_magnitude(elem(current_state, 2)) < 0.01 do
      new_state = put_elem(current_state, get_attr_index(:vel), [0.0, 0.0])
      :ets.insert(:particle_data, new_state)
      broadcast_update(new_state)
      {:reply, :ok, new_state}
    else
      bounds = CollisionEngine.world_bounds()
      {id, pos, vel, radius, _mass, color, current_spin, current_roll} = current_state

      friction = CollisionEngine.friction_coefficient()
      [vx, vy] = vel
      damping_factor = :math.pow(1.0 - friction, dt)
      damped_vel = [vx * damping_factor, vy * damping_factor]

      # --- Calcula ambas as rotações ---
      distance_moved = Physics.velocity_magnitude(damped_vel) * dt
      # Rolagem é a distância acumulada
      new_roll_distance = current_roll + distance_moved
      # Giro é um ângulo que também aumenta com a distância
      # O fator 0.5 torna o giro mais sutil
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
          @game_events_topic,
          {:ball_pocketed, id, color}
        )

        :ets.delete(:particle_data, id)
        {:stop, :normal, :ok, current_state}
      else
        new_state =
          current_state
          |> put_elem(get_attr_index(:pos), final_pos)
          |> put_elem(get_attr_index(:vel), final_vel)
          |> put_elem(get_attr_index(:spin_angle), new_spin_angle)
          |> put_elem(get_attr_index(:roll_distance), new_roll_distance)

        :ets.insert(:particle_data, new_state)
        broadcast_update(new_state)
        {:reply, :ok, new_state}
      end
    end
  end

  @impl true
  def handle_cast({:update_after_collision, new_velocity, new_position}, current_state) do
    new_state =
      current_state
      |> put_elem(get_attr_index(:vel), new_velocity)
      |> put_elem(get_attr_index(:pos), new_position)
      # Reseta a rolagem na colisão
      |> put_elem(get_attr_index(:roll_distance), 0.0)

    :ets.insert(:particle_data, new_state)
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:apply_force, [fx, fy]}, current_state) do
    {_id, _pos, [vx, vy], _radius, mass, _color, _spin, _roll} = current_state
    new_velocity = [vx + fx / mass, vy + fy / mass]

    new_state =
      current_state
      |> put_elem(get_attr_index(:vel), new_velocity)
      # Reseta ambos na tacada
      |> put_elem(get_attr_index(:spin_angle), 0.0)
      |> put_elem(get_attr_index(:roll_distance), 0.0)

    :ets.insert(:particle_data, new_state)
    {:noreply, new_state}
  end

  @spec broadcast_update(particle_state()) :: :ok
  def broadcast_update(particle_tuple) do
    payload = %{
      id: elem(particle_tuple, get_attr_index(:id)),
      pos: elem(particle_tuple, get_attr_index(:pos)),
      vel: elem(particle_tuple, get_attr_index(:vel)),
      radius: elem(particle_tuple, get_attr_index(:radius)),
      color: elem(particle_tuple, get_attr_index(:color)),
      spin_angle: elem(particle_tuple, get_attr_index(:spin_angle)),
      roll_distance: elem(particle_tuple, get_attr_index(:roll_distance))
    }

    Phoenix.PubSub.broadcast(SnookerGameEx.PubSub, @simulation_topic, {:particle_moved, payload})
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
