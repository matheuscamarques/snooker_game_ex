defmodule SnookerGameEx.Particle do
  @moduledoc """
  Represents a single particle (a ball) in the simulation.

  Each particle is an independent `GenServer` process that holds its own state
  (position, velocity, etc.). It responds to commands from the `CollisionEngine`
  to move, and updates its state after collisions. It also broadcasts its
  state changes via Phoenix PubSub to the frontend for rendering.
  """
  use GenServer

  alias SnookerGameEx.Physics
  alias SnookerGameEx.CollisionEngine

  @simulation_topic "particle_updates"

  @typedoc "A tuple representing the full state of a particle."
  @type particle_state :: {id :: any(), pos :: list(float()), vel :: list(float()), radius :: float(), mass :: float(), color :: String.t()}

  @doc "Starts a particle GenServer."
  @spec start_link(list) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  @doc "Returns a `via` tuple for registering and looking up the process by its ID."
  @spec via_tuple(any()) :: {:via, module(), {module(), any()}}
  def via_tuple(id), do: {:via, Registry, {SnookerGameEx.ParticleRegistry, id}}

  @doc """
  Initializes the Particle GenServer.

  It takes the initial properties of the particle (id, position, velocity, etc.),
  constructs the initial state tuple, and inserts it into the shared `:particle_data`
  ETS table for fast, global access by the `CollisionEngine`.
  """
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

  @doc """
  Handles the synchronous `move` command from the `CollisionEngine`.

  For each simulation step, this function updates the particle's position based
  on its current velocity. It also handles collisions with the table walls.
  If the particle's velocity is below a small threshold, its velocity is zeroed out
  to prevent indefinite "jittering" movement.
  """
  @impl true
  def handle_call({:move, dt}, _from, current_state) do
    # If the particle is nearly stationary, stop it completely.
    if Physics.velocity_magnitude(elem(current_state, 2)) < 0.01 do
      new_state = put_elem(current_state, get_attr_index(:vel), [0.0, 0.0])
      :ets.insert(:particle_data, new_state)
      broadcast_update(new_state)
      {:reply, :ok, new_state}
    else
      # Otherwise, calculate its new position and handle wall collisions.
      bounds = CollisionEngine.world_bounds()
      {_id, pos, vel, radius, _mass, _color} = current_state

      [px, py] = pos
      [vx, vy] = vel
      # Basic Euler integration for the new position.
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

  @doc """
  Handles the asynchronous update after a collision has been resolved.

  The `CollisionEngine` calculates the results of a collision and sends this
  update to the two particles involved. This function applies the new
  velocity and position to the particle's state.
  """
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

  @doc """
  Handles applying an external force, such as a cue strike from the player.

  This changes the particle's velocity based on the force and its mass (F=ma).
  """
  @impl true
  def handle_cast({:apply_force, [fx, fy]}, current_state) do
    {_id, _pos, [vx, vy], _radius, mass, _color} = current_state
    # F = ma => a = F/m. The change in velocity is an impulse.
    new_velocity = [vx + fx / mass, vy + fy / mass]
    new_state = put_elem(current_state, get_attr_index(:vel), new_velocity)
    :ets.insert(:particle_data, new_state)
    {:noreply, new_state}
  end

  @doc """
  Broadcasts the particle's current visual state to the frontend via PubSub.
  """
  @spec broadcast_update(particle_state()) :: :ok
  def broadcast_update(particle_tuple) do
    # We only send the data needed for rendering to the client.
    payload = %{
      id: elem(particle_tuple, get_attr_index(:id)),
      pos: elem(particle_tuple, get_attr_index(:pos)),
      radius: elem(particle_tuple, get_attr_index(:radius)),
      color: elem(particle_tuple, get_attr_index(:color))
    }

    Phoenix.PubSub.broadcast(SnookerGameEx.PubSub, @simulation_topic, {:particle_moved, payload})
  end

  @doc """
  Returns the integer index for a given attribute in the particle's state tuple.

  This avoids using magic numbers and makes the code more readable and maintainable.
  """
  @spec get_attr_index(atom()) :: non_neg_integer()
  def get_attr_index(attr) do
    case attr do
      :id -> 0
      :pos -> 1
      :vel -> 2
      :radius -> 3
      :mass -> 4
      :color -> 5
      _ -> raise ArgumentError, "Unknown attribute: #{inspect(attr)}"
    end
  end
end
