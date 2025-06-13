defmodule SnookerGameEx.Physics do
  @moduledoc """
  A module for physics computations, optimized with `Nx` (Numerical Elixir).

  It handles wall collision logic and contains the core `defn` functions for
  batch-processing particle-particle collisions using tensor operations, which
  is significantly more performant than processing them one by one.
  """
  import Nx.Defn

  @typedoc "A map of tensors representing the batched state of many particles."
  @type batch_states :: %{
          pos: Nx.Tensor.t(),
          vel: Nx.Tensor.t(),
          radius: Nx.Tensor.t(),
          mass: Nx.Tensor.t()
        }

  @typedoc "A map representing the rectangular boundaries of the game world."
  @type world_bounds :: %{x: float(), y: float(), w: float(), h: float()}

  @doc "Calculates the magnitude (length) of a velocity vector."
  @spec velocity_magnitude([float()]) :: float()
  def velocity_magnitude([vx, vy]), do: :math.sqrt(vx * vx + vy * vy)

  @doc "Handles the collision of a single particle with the world boundaries (walls)."
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
  Filters candidate pairs to find only those that are truly colliding (Narrow Phase).

  This `defn` runs on the GPU (if available). It takes a tensor of candidate pairs
  (from the Quadtree) and calculates the distance between each pair. If the distance
  is less than the sum of their radii, they are considered to be colliding.
  """
  @spec get_colliding_pairs(batch_states(), Nx.Tensor.t()) :: Nx.Tensor.t()
  defn get_colliding_pairs(states, candidate_pairs) do
    %{pos: positions, radius: radii} = states
    i_indices = Nx.slice_along_axis(candidate_pairs, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    j_indices = Nx.slice_along_axis(candidate_pairs, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])
    pos_i = Nx.take(positions, i_indices)
    pos_j = Nx.take(positions, j_indices)
    r_i = Nx.take(radii, i_indices)
    r_j = Nx.take(radii, j_indices)
    diff = pos_i - pos_j
    dist_sq = Nx.sum(diff * diff, axes: [1], keep_axes: true)
    radius_sum = r_i + r_j
    min_dist_sq = radius_sum * radius_sum
    collision_mask = dist_sq < min_dist_sq
    candidate_pairs[Nx.squeeze(collision_mask)] |> Nx.reshape({:auto, 2})
  end

  @doc """
  A wrapper function that calls the core `defn` logic and deserializes the
  resulting tensors back into a list of maps for easier dispatching.
  """
  @spec calculate_collision_responses(batch_states(), Nx.Tensor.t()) :: list(map())
  def calculate_collision_responses(states, colliding_pairs) do
    {i_indices, j_indices, new_vel_i, new_vel_j, new_pos_i, new_pos_j} =
      do_calculate_collision_responses(states, colliding_pairs)

    i_list = Nx.to_list(i_indices)
    j_list = Nx.to_list(j_indices)
    new_vel_i_list = Nx.to_list(new_vel_i)
    new_vel_j_list = Nx.to_list(new_vel_j)
    new_pos_i_list = Nx.to_list(new_pos_i)
    new_pos_j_list = Nx.to_list(new_pos_j)

    # Combine the results back into a more manageable data structure.
    Enum.zip([i_list, j_list, new_vel_i_list, new_vel_j_list, new_pos_i_list, new_pos_j_list])
    |> Enum.map(fn {idx_i, idx_j, vel_i, vel_j, pos_i, pos_j} ->
      %{
        index_a: idx_i,
        index_b: idx_j,
        new_vel_a: vel_i,
        new_vel_b: vel_j,
        new_pos_a: pos_i,
        new_pos_b: pos_j
      }
    end)
  end

  @doc """
  Calculates the new velocities and positions for pairs of colliding particles.
  This `defn` contains the main collision physics logic, performing calculations
  for all colliding pairs simultaneously.

  The process involves:
  1. Calculating the impulse based on the conservation of momentum and the coefficient of restitution.
  2. Updating the velocities of the particles based on this impulse.
  3. Calculating and applying a positional correction to resolve interpenetration
     (i.e., to stop the balls from sticking together).
  """
  @spec do_calculate_collision_responses(batch_states(), Nx.Tensor.t()) ::
          {Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t(),
           Nx.Tensor.t()}
  defn do_calculate_collision_responses(states, colliding_pairs) do
    # 1. Extract data for the particles involved in the collision
    i_indices = Nx.slice_along_axis(colliding_pairs, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    j_indices = Nx.slice_along_axis(colliding_pairs, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])
    pos_i = Nx.take(states.pos, i_indices)
    pos_j = Nx.take(states.pos, j_indices)
    vel_i = Nx.take(states.vel, i_indices)
    vel_j = Nx.take(states.vel, j_indices)
    m_i = Nx.take(states.mass, i_indices)
    m_j = Nx.take(states.mass, j_indices)
    r_i = Nx.take(states.radius, i_indices)
    r_j = Nx.take(states.radius, j_indices)

    # 2. Calculate collision response (new velocities)
    normal = pos_i - pos_j
    distance = Nx.sqrt(Nx.sum(normal * normal, axes: [1], keep_axes: true))
    # Add epsilon to avoid division by zero
    unit_normal = normal / (distance + 1.0e-6)
    velocity_diff = vel_i - vel_j
    dot_product = Nx.sum(velocity_diff * unit_normal, axes: [1], keep_axes: true)

    # Coefficient of restitution (elasticity)
    restitution = 0.9
    # Particles are moving towards each other if the dot product of their
    # velocity difference and the normal is negative.
    is_approaching = dot_product < 0

    # Calculate impulse (instantaneous change in momentum)
    impulse_magnitude = -(1 + restitution) * dot_product / (1 / m_i + 1 / m_j)
    impulse = impulse_magnitude * unit_normal

    # Only apply impulse if particles are approaching
    broadcasted_mask = Nx.broadcast(is_approaching, Nx.shape(impulse))
    zero_impulse = Nx.broadcast(0.0, Nx.shape(impulse))
    effective_impulse = Nx.select(broadcasted_mask, impulse, zero_impulse)

    # Update velocities based on impulse (p = mv => v = p/m)
    new_vel_i = vel_i + effective_impulse / m_i
    new_vel_j = vel_j - effective_impulse / m_j

    # 3. Resolve interpenetration (positional correction) to prevent sticking
    # How strong the correction is (0.2 to 0.8 is a good range)
    percent = 0.4
    # A small margin to prevent "jittering" on resting contacts
    slop = 0.01

    # Calculate the penetration depth.
    # If the balls overlap, `distance` < `r_i + r_j`, so the result is positive.
    penetration_depth = r_i + r_j - distance

    # The magnitude of the correction to be applied, ensuring it's not negative.
    # The `slop` creates a small dead zone for stability.
    correction_amount = Nx.max(penetration_depth - slop, 0.0)

    # The total correction is distributed based on inverse mass.
    total_inverse_mass = 1 / m_i + 1 / m_j
    # Avoid division by zero if both masses are infinite (unlikely here)
    total_inverse_mass = Nx.select(total_inverse_mass > 0, total_inverse_mass, 1.0)
    correction_magnitude = correction_amount / total_inverse_mass * percent

    # The correction vector points along the collision normal.
    correction = correction_magnitude * unit_normal

    # Apply positional correction by distributing the movement based on mass.
    # Heavier particles move less.
    new_pos_i = pos_i + correction * (1 / m_i)
    new_pos_j = pos_j - correction * (1 / m_j)

    {i_indices, j_indices, new_vel_i, new_vel_j, new_pos_i, new_pos_j}
  end
end
