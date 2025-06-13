defmodule SnookerGameEx.Particle do
  @moduledoc "Representa uma única partícula (bola) na simulação."
  use GenServer

  alias SnookerGameEx.Physics
  alias SnookerGameEx.CollisionEngine

  @simulation_topic "particle_updates"

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
        Keyword.get(opts, :color, "white")
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
      {_id, pos, vel, radius, _mass, _color} = current_state

      [px, py] = pos
      [vx, vy] = vel
      new_pos_integrated = [px + vx * dt, py + vy * dt]

      {final_pos, final_vel} =
        Physics.handle_wall_collision(
          %{pos: new_pos_integrated, vel: vel, radius: radius},
          bounds
        )

      new_state =
        current_state
        |> put_elem(get_attr_index(:pos), final_pos)
        |> put_elem(get_attr_index(:vel), final_vel)

      :ets.insert(:particle_data, new_state)
      broadcast_update(new_state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:update_after_collision, new_velocity, new_position}, current_state) do
    new_state =
      current_state
      |> put_elem(get_attr_index(:vel), new_velocity)
      |> put_elem(get_attr_index(:pos), new_position)

    :ets.insert(:particle_data, new_state)
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:apply_force, [fx, fy]}, current_state) do
    {_id, _pos, [vx, vy], _radius, mass, _color} = current_state
    new_velocity = [vx + fx / mass, vy + fy / mass]
    new_state = put_elem(current_state, get_attr_index(:vel), new_velocity)
    :ets.insert(:particle_data, new_state)
    {:noreply, new_state}
  end

  defp broadcast_update(particle_tuple) do
    payload = %{
      id: elem(particle_tuple, get_attr_index(:id)),
      pos: elem(particle_tuple, get_attr_index(:pos)),
      radius: elem(particle_tuple, get_attr_index(:radius)),
      color: elem(particle_tuple, get_attr_index(:color))
    }

    Phoenix.PubSub.broadcast(SnookerGameEx.PubSub, @simulation_topic, {:particle_moved, payload})
  end

  def get_attr_index(attr) do
    case attr do
      :id -> 0
      :pos -> 1
      :vel -> 2
      :radius -> 3
      :mass -> 4
      :color -> 5
      _ -> raise ArgumentError, "Atributo desconhecido: #{inspect(attr)}"
    end
  end
end
