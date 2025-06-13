defmodule SnookerGameEx.Physics do
  @moduledoc "Módulo de computação de física, otimizado com `Nx` (`Numerical Elixir`)."
  import Nx.Defn

  @typep batch_states :: %{
           pos: Nx.Tensor.t(),
           vel: Nx.Tensor.t(),
           radius: Nx.Tensor.t(),
           mass: Nx.Tensor.t()
         }
  @typep world_bounds :: %{min_x: float(), max_x: float(), min_y: float(), max_y: float()}

  @doc "Calcula a magnitude (comprimento) de um vetor de velocidade."
  def velocity_magnitude([vx, vy]), do: :math.sqrt(vx * vx + vy * vy)

  @doc "Lida com a colisão de uma partícula com as paredes do mundo."
  @doc "Lida com a colisão de uma partícula com as paredes do mundo."
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

  @doc "Filtra os pares candidatos para encontrar apenas os que estão realmente colidindo."
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

  @doc "Deserializa os tensores de resultado em uma lista de mapas para despacho."
  def calculate_collision_responses(states, colliding_pairs) do
    {i_indices, j_indices, new_vel_i, new_vel_j, new_pos_i, new_pos_j} =
      do_calculate_collision_responses(states, colliding_pairs)

    i_list = Nx.to_list(i_indices)
    j_list = Nx.to_list(j_indices)
    new_vel_i_list = Nx.to_list(new_vel_i)
    new_vel_j_list = Nx.to_list(new_vel_j)
    new_pos_i_list = Nx.to_list(new_pos_i)
    new_pos_j_list = Nx.to_list(new_pos_j)

    # Combina os resultados de volta em uma estrutura de dados mais fácil de manusear.
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
  Calcula as novas velocidades e posições para pares de partículas em colisão.
  Esta função contém a lógica principal da física de colisão.
  """
  defn do_calculate_collision_responses(states, colliding_pairs) do
    # 1. Extrai os dados das partículas envolvidas na colisão
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

    # 2. Calcula a resposta da colisão (novas velocidades)
    normal = pos_i - pos_j
    distance = Nx.sqrt(Nx.sum(normal * normal, axes: [1], keep_axes: true))
    # Adiciona epsilon para evitar divisão por zero
    unit_normal = normal / (distance + 1.0e-6)
    velocity_diff = vel_i - vel_j
    dot_product = Nx.sum(velocity_diff * unit_normal, axes: [1], keep_axes: true)

    # Coeficiente de restituição (elasticidade)
    restitution = 0.9
    # As partículas estão se movendo uma em direção à outra
    is_approaching = dot_product < 0

    # Calcula o impulso (mudança instantânea de momento)
    impulse_magnitude = -(1 + restitution) * dot_product / (1 / m_i + 1 / m_j)
    impulse = impulse_magnitude * unit_normal

    # Aplica o impulso apenas se as partículas estiverem se aproximando
    broadcasted_mask = Nx.broadcast(is_approaching, Nx.shape(impulse))
    zero_impulse = Nx.broadcast(0.0, Nx.shape(impulse))
    effective_impulse = Nx.select(broadcasted_mask, impulse, zero_impulse)

    # Atualiza as velocidades com base no impulso
    new_vel_i = vel_i + effective_impulse / m_i
    new_vel_j = vel_j - effective_impulse / m_j

    # 3. Resolve a interpenetração (correção de posição) para evitar que grudem
    # Quão forte é a correção (0.2 a 0.8 é um bom intervalo)
    percent = 0.4
    # Uma pequena margem para evitar "tremores" em contatos de repouso
    slop = 0.01

    # --- INÍCIO DA CORREÇÃO ---
    # CORRIGIDO: Calculamos a profundidade da penetração.
    # Se as bolas se sobrepõem, `distance` < `r_i + r_j`, então o resultado é positivo.
    penetration_depth = r_i + r_j - distance

    # A magnitude da correção a ser aplicada, garantindo que não seja negativa.
    # O `slop` cria uma pequena zona morta para estabilidade.
    correction_amount = Nx.max(penetration_depth - slop, 0.0)

    # A correção total é distribuída com base na massa inversa.
    total_inverse_mass = 1 / m_i + 1 / m_j
    # Evita divisão por zero se ambas as massas forem infinitas (improvável aqui)
    total_inverse_mass = Nx.select(total_inverse_mass > 0, total_inverse_mass, 1.0)
    correction_magnitude = correction_amount / total_inverse_mass * percent

    # O vetor de correção aponta ao longo da normal da colisão.
    correction = correction_magnitude * unit_normal
    # --- FIM DA CORREÇÃO ---

    # Aplica a correção de posição distribuindo o movimento com base na massa.
    # Partículas mais pesadas se movem menos.
    # A correção é aplicada independentemente da direção
    effective_correction = correction
    new_pos_i = pos_i + effective_correction * (1 / m_i)
    new_pos_j = pos_j - effective_correction * (1 / m_j)

    {i_indices, j_indices, new_vel_i, new_vel_j, new_pos_i, new_pos_j}
  end
end
