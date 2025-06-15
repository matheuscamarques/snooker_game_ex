defmodule SnookerGameEx.Physics do
  @moduledoc """
  Physics computations optimized with Nx.
  This version uses manual list manipulation for updates to ensure
  maximum compatibility with all versions of Nx.
  """
  import Nx.Defn

  @typedoc "Batch state: tensors for particle properties"
  @type batch_states :: %{
          pos: Nx.Tensor.t(),
          vel: Nx.Tensor.t(),
          radius: Nx.Tensor.t(),
          mass: Nx.Tensor.t()
        }

  @typedoc "World boundaries definition"
  @type world_bounds :: %{x: float(), y: float(), w: float(), h: float()}

  def velocity_magnitude([vx, vy]), do: :math.sqrt(vx * vx + vy * vy)

  def handle_wall_collision(particle, world_bounds) do
    %{pos: [x, y], vel: [vx, vy], radius: r} = particle
    %{x: min_x, y: min_y, w: width, h: height} = world_bounds
    max_x = min_x + width
    max_y = min_y + height
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

  defn get_colliding_pairs(states, candidate_pairs) do
    i = Nx.slice_along_axis(candidate_pairs, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
    j = Nx.slice_along_axis(candidate_pairs, 1, 1, axis: 1) |> Nx.squeeze(axes: [1])
    pos_i = Nx.take(states.pos, i)
    pos_j = Nx.take(states.pos, j)
    r_i = Nx.take(states.radius, i)
    r_j = Nx.take(states.radius, j)
    diff = pos_i - pos_j
    dist_sq = Nx.sum(diff * diff, axes: [1], keep_axes: true)
    min_dist_sq = (r_i + r_j) ** 2
    collision_mask = Nx.squeeze(dist_sq < min_dist_sq)
    candidate_pairs[collision_mask] |> Nx.reshape({:auto, 2})
  end

  def calculate_collision_responses(states, colliding_pairs) do
    restitution = 0.9
    correction_percent = 0.8
    correction_slop = 0.01

    if Nx.axis_size(colliding_pairs, 0) == 0 do
      nil
    else
      do_calculate_collision_responses(
        states,
        colliding_pairs,
        restitution,
        correction_percent,
        correction_slop
      )
    end
  end

  defn do_calculate_collision_responses(states, colliding_pairs, restitution, percent, slop) do
    inv_mass = 1.0 / (states.mass + 1.0e-6)
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
    normal = pos_i - pos_j
    distance = Nx.LinAlg.norm(normal, axes: [1], keep_axes: true)
    safe_distance = distance + 1.0e-6
    unit_normal = normal / safe_distance
    rel_vel = vel_i - vel_j
    approach_velocity = Nx.sum(rel_vel * unit_normal, axes: [1], keep_axes: true)
    is_approaching = approach_velocity < 0
    total_inv_mass = inv_m_i + inv_m_j
    impulse_mag = -(1 + restitution) * approach_velocity / (total_inv_mass + 1.0e-6)
    impulse = impulse_mag * unit_normal
    mask = Nx.select(is_approaching, 1.0, 0.0)
    effective_impulse = impulse * mask
    new_vel_i = vel_i + effective_impulse * inv_m_i
    new_vel_j = vel_j - effective_impulse * inv_m_j
    penetration = r_i + r_j - distance
    correction_amount = Nx.max(penetration - slop, 0.0)
    correction_mag = correction_amount * percent / (total_inv_mass + 1.0e-6)
    correction = correction_mag * unit_normal
    new_pos_i = pos_i + correction * inv_m_i
    new_pos_j = pos_j - correction * inv_m_j
    {i, j, new_vel_i, new_vel_j, new_pos_i, new_pos_j}
  end

  @doc """
  Applies collision updates by manually reconstructing the tensors.
  This approach is guaranteed to be compatible with all versions of Nx.
  """
  def apply_collision_updates(states, collision_results) do
    # 1. Extrair os dados de atualização e convertê-los para listas Elixir.
    {i_tensor, j_tensor, new_vel_i, new_vel_j, new_pos_i, new_pos_j} = collision_results
    i_list = Nx.to_list(i_tensor)
    j_list = Nx.to_list(j_tensor)
    vel_i_list = Nx.to_list(new_vel_i)
    vel_j_list = Nx.to_list(new_vel_j)
    pos_i_list = Nx.to_list(new_pos_i)
    pos_j_list = Nx.to_list(new_pos_j)

    # 2. Criar um mapa para acesso rápido às atualizações.
    updates =
      ((i_list
        |> Enum.zip(pos_i_list)
        |> Enum.zip(vel_i_list)
        |> Enum.map(fn {{index, pos}, vel} -> {index, {pos, vel}} end)) ++
         (j_list
          |> Enum.zip(pos_j_list)
          |> Enum.zip(vel_j_list)
          |> Enum.map(fn {{index, pos}, vel} -> {index, {pos, vel}} end)))
      |> Map.new()

    # 3. Converter os tensores originais para listas Elixir.
    original_pos_list = Nx.to_list(states.pos)
    original_vel_list = Nx.to_list(states.vel)

    # 4. Construir as novas listas, aplicando as atualizações.
    {final_pos_list, final_vel_list} =
      Enum.with_index(original_pos_list)
      |> Enum.map(fn {original_pos, index} ->
        original_vel = Enum.at(original_vel_list, index)

        case Map.get(updates, index) do
          # Se houver uma atualização para este índice, use-a.
          {new_pos, new_vel} -> {new_pos, new_vel}
          # Caso contrário, mantenha os valores originais.
          nil -> {original_pos, original_vel}
        end
      end)
      |> Enum.unzip()

    # 5. Converter as listas finais de volta para tensores.
    final_pos_tensor = Nx.tensor(final_pos_list)
    final_vel_tensor = Nx.tensor(final_vel_list)

    # 6. Retornar o novo mapa de estados.
    %{states | pos: final_pos_tensor, vel: final_vel_tensor}
  end

  def pocketed?(particle_pos, pockets, pocket_radius) do
    [px, py] = particle_pos

    Enum.any?(pockets, fn pocket ->
      [pocket_x, pocket_y] = pocket.pos
      dist_sq = :math.pow(px - pocket_x, 2) + :math.pow(py - pocket_y, 2)
      dist_sq < :math.pow(pocket_radius, 2)
    end)
  end
end
