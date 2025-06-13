defmodule SnookerGameEx.Physics do
  @moduledoc """
  Physics computations optimized with Nx, featuring:
  - Processamento vetorizado em GPU
  - Tratamento numérico robusto
  - Operações de tensor eficientes
  """
  import Nx.Defn

  @typedoc "Batch state: tensors for particle properties"
  @type batch_states :: %{
          # {num_particles, 2}
          pos: Nx.Tensor.t(),
          # {num_particles, 2}
          vel: Nx.Tensor.t(),
          # {num_particles, 1}
          radius: Nx.Tensor.t(),
          # {num_particles, 1}
          mass: Nx.Tensor.t()
        }

  @typedoc "World boundaries definition"
  @type world_bounds :: %{x: float(), y: float(), w: float(), h: float()}

  @doc "Calculates the magnitude (length) of a velocity vector."
  @spec velocity_magnitude([float()]) :: float()
  def velocity_magnitude([vx, vy]), do: :math.sqrt(vx * vx + vy * vy)

  @doc """
  Handles the collision of a single particle with the world boundaries.

  This function is kept for compatibility with logic that processes one particle
  at a time, such as individual Particle GenServers.
  """
  @spec handle_wall_collision(
          particle :: %{pos: [float()], vel: [float()], radius: float()},
          world_bounds :: world_bounds()
        ) :: {[float()], [float()]}
  def handle_wall_collision(particle, world_bounds) do
    %{pos: [x, y], vel: [vx, vy], radius: r} = particle
    %{x: min_x, y: min_y, w: width, h: height} = world_bounds

    max_x = min_x + width
    max_y = min_y + height

    # Damping factor simulates energy loss on wall impact.
    damping = 0.8

    {new_vx, new_x} =
      cond do
        x - r < min_x -> {-vx * damping, min_x + r}
        x + r > max_x -> {-vx * damping, max_x - r}
        true -> {vx, x}
      end

    {new_vy, new_y} =
      cond do
        y - r < min_y -> {-vy * damping, min_y + r}
        y + r > max_y -> {-vy * damping, max_y - r}
        true -> {vy, y}
      end

    {[new_x, new_y], [new_vx, new_vy]}
  end

  @doc """
  Batch-processes all wall collisions using `defn`.
  """
  @spec handle_wall_collisions(
          states :: batch_states(),
          world_bounds :: world_bounds(),
          damping :: float()
        ) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  defn handle_wall_collisions(states, world_bounds, damping) do
    %{pos: positions, vel: velocities, radius: radii} = states
    %{x: min_x, y: min_y, w: width, h: height} = world_bounds
    max_x = min_x + width
    max_y = min_y + height

    # Use Nx.slice_along_axis, the correct syntax inside defn.
    x = Nx.slice_along_axis(positions, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    y = Nx.slice_along_axis(positions, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])
    vx = Nx.slice_along_axis(velocities, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    vy = Nx.slice_along_axis(velocities, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])
    r = Nx.squeeze(radii, axes: [1])

    # X-axis collisions
    left_collide = x - r < min_x
    right_collide = x + r > max_x

    new_vx =
      Nx.select(left_collide, -vx * damping, Nx.select(right_collide, -vx * damping, vx))

    new_x =
      Nx.select(left_collide, min_x + r, Nx.select(right_collide, max_x - r, x))

    # Y-axis collisions
    top_collide = y - r < min_y
    bottom_collide = y + r > max_y

    new_vy =
      Nx.select(top_collide, -vy * damping, Nx.select(bottom_collide, -vy * damping, vy))

    new_y =
      Nx.select(top_collide, min_y + r, Nx.select(bottom_collide, max_y - r, y))

    # Combine into tensors
    new_pos = Nx.stack([new_x, new_y], axis: 1)
    new_vel = Nx.stack([new_vx, new_vy], axis: 1)

    {new_pos, new_vel}
  end

  @doc "Filters candidate pairs to find only those that are truly colliding."
  @spec get_colliding_pairs(batch_states(), Nx.Tensor.t()) :: Nx.Tensor.t()
  defn get_colliding_pairs(states, candidate_pairs) do
    # Use Nx.slice_along_axis for valid defn syntax.
    i = Nx.slice_along_axis(candidate_pairs, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    j = Nx.slice_along_axis(candidate_pairs, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])

    pos_i = Nx.take(states.pos, i)
    pos_j = Nx.take(states.pos, j)
    r_i = Nx.take(states.radius, i)
    r_j = Nx.take(states.radius, j)

    diff = pos_i - pos_j
    dist_sq = Nx.sum(diff * diff, axes: [1], keep_axes: true)
    min_dist_sq = (r_i + r_j) ** 2

    # Squeeze the mask to be 1D for correct indexing
    collision_mask = Nx.squeeze(dist_sq < min_dist_sq)
    candidate_pairs[collision_mask] |> Nx.reshape({:auto, 2})
  end

  @doc "Calculates collision responses and formats the output."
  @spec calculate_collision_responses(batch_states(), Nx.Tensor.t()) :: list(map())
  def calculate_collision_responses(states, colliding_pairs) do
    # These could also be passed as arguments for runtime tweaking
    restitution = 0.9
    correction_percent = 0.4
    correction_slop = 0.01

    # Return early if there's nothing to do
    if Nx.axis_size(colliding_pairs, 0) == 0 do
      []
    else
      {i_indices, j_indices, new_vel_i, new_vel_j, new_pos_i, new_pos_j} =
        do_calculate_collision_responses(
          states,
          colliding_pairs,
          restitution,
          correction_percent,
          correction_slop
        )

      # Bulk conversion is more performant than looping and converting one-by-one.
      i_list = Nx.to_list(i_indices)
      j_list = Nx.to_list(j_indices)
      new_vel_i_list = Nx.to_list(new_vel_i)
      new_vel_j_list = Nx.to_list(new_vel_j)
      new_pos_i_list = Nx.to_list(new_pos_i)
      new_pos_j_list = Nx.to_list(new_pos_j)

      for {idx_i, idx_j, vel_i, vel_j, pos_i, pos_j} <-
            List.zip([
              i_list,
              j_list,
              new_vel_i_list,
              new_vel_j_list,
              new_pos_i_list,
              new_pos_j_list
            ]) do
        %{
          index_a: idx_i,
          index_b: idx_j,
          new_vel_a: vel_i,
          new_vel_b: vel_j,
          new_pos_a: pos_i,
          new_pos_b: pos_j
        }
      end
    end
  end

  @doc "Core `defn` for calculating physics responses to collisions."
  @spec do_calculate_collision_responses(
          states :: batch_states(),
          colliding_pairs :: Nx.Tensor.t(),
          restitution :: float(),
          percent :: float(),
          slop :: float()
        ) ::
          {Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(),
           Nx.Tensor.t()}
  defn do_calculate_collision_responses(states, colliding_pairs, restitution, percent, slop) do
    # Precompute inverse masses once for efficiency
    inv_mass = 1.0 / (states.mass + 1.0e-6)

    # Use Nx.slice_along_axis for valid defn syntax.
    i = Nx.slice_along_axis(colliding_pairs, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    j = Nx.slice_along_axis(colliding_pairs, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])

    pos_i = Nx.take(states.pos, i)
    pos_j = Nx.take(states.pos, j)
    vel_i = Nx.take(states.vel, i)
    vel_j = Nx.take(states.vel, j)
    r_i = Nx.take(states.radius, i)
    r_j = Nx.take(states.radius, j)
    inv_m_i = Nx.take(inv_mass, i)
    inv_m_j = Nx.take(inv_mass, j)

    # Vector calculations
    normal = pos_i - pos_j
    distance = Nx.LinAlg.norm(normal, axes: [1], keep_axes: true)
    safe_distance = distance + 1.0e-6
    unit_normal = normal / safe_distance

    # Relative velocity and approach check
    rel_vel = vel_i - vel_j
    approach_velocity = Nx.sum(rel_vel * unit_normal, axes: [1], keep_axes: true)
    is_approaching = approach_velocity < 0

    # Impulse calculation with safe division
    total_inv_mass = inv_m_i + inv_m_j
    impulse_mag = -(1 + restitution) * approach_velocity / (total_inv_mass + 1.0e-6)
    impulse = impulse_mag * unit_normal

    # Apply impulse only to approaching particles using a broadcastable mask
    mask = Nx.select(is_approaching, 1.0, 0.0)
    effective_impulse = impulse * mask

    new_vel_i = vel_i + effective_impulse * inv_m_i
    new_vel_j = vel_j - effective_impulse * inv_m_j

    # Positional correction to resolve overlap
    penetration = r_i + r_j - distance
    correction_amount = Nx.max(penetration - slop, 0.0)
    correction_mag = correction_amount * percent / (total_inv_mass + 1.0e-6)
    correction = correction_mag * unit_normal

    new_pos_i = pos_i + correction * inv_m_i
    new_pos_j = pos_j - correction * inv_m_j

    {i, j, new_vel_i, new_vel_j, new_pos_i, new_pos_j}
  end
end
