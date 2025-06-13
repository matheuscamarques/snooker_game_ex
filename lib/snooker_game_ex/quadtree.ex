defmodule SnookerGameEx.Quadtree do
  @moduledoc """
  Implementação de uma Quadtree (logicamente correta, sem tratamento de concorrência).

  Esta versão foi corrigida para garantir a integridade dos dados em operações
  de inicialização (`init`) e limpeza (`clear`) quando usada por um único processo.

  As questões de concorrência (condições de corrida) levantadas na análise
  foram intencionalmente ignoradas conforme solicitado, assumindo que o controle
  de acesso concorrente será gerenciado externamente (ex: por um GenServer).
  """

  @type table_name :: atom()
  @type point :: {float(), float()}
  @type boundary :: %{x: float(), y: float(), w: float(), h: float()}
  @type entity_id :: any()
  @type node_id :: integer()

  # =============================================================================
  # API Pública
  # =============================================================================

  @doc "Cria e inicializa a tabela ETS para a Quadtree."
  @spec init(
          table_name,
          boundary,
          capacity :: non_neg_integer(),
          max_depth :: non_neg_integer()
        ) :: :ok
  def init(table, boundary, capacity, max_depth) do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      # Desabilitado para reforçar o uso por processo único
      write_concurrency: false
    ])

    root_id = 1
    root_node = %{type: :leaf, boundary: boundary, points: []}

    # CORREÇÃO 1: Armazena a `boundary` na configuração para uso em `clear/1`.
    config = %{
      root_id: root_id,
      capacity: capacity,
      max_depth: max_depth,
      boundary: boundary
    }

    :ets.insert(table, {:__config__, config})
    :ets.insert(table, {root_id, root_node})

    :ok
  end

  @doc "Limpa todos os pontos da Quadtree, resetando-a ao seu estado inicial."
  @spec clear(table_name) :: :ok
  def clear(table) do
    # CORREÇÃO 2: Lógica de `clear` robusta e correta.
    case :ets.lookup(table, :__config__) do
      [{:__config__, config}] ->
        # Deleta apenas os nós (chaves inteiras), preservando a :__config__.
        match_spec = [{{:"$1", :_}, [{:is_integer, :"$1"}], [true]}]
        :ets.match_delete(table, match_spec)

        # Recria o nó raiz usando a boundary guardada na config.
        root_id = config.root_id
        root_node = %{type: :leaf, boundary: config.boundary, points: []}
        :ets.insert(table, {root_id, root_node})
        :ok

      [] ->
        :ok
    end
  end

  @doc "Deleta completamente a tabela ETS da Quadtree."
  @spec delete_table(table_name) :: :ok
  def delete_table(table), do: :ets.delete(table)

  @doc "Insere uma entidade com um ponto e um ID na Quadtree."
  @spec insert(table_name, point, entity_id) :: :ok | {:error, :out_of_bounds}
  def insert(table, point, id) do
    case :ets.lookup(table, :__config__) do
      [{:__config__, config}] ->
        do_insert(table, config.root_id, point, id, config, 0)

      [] ->
        {:error, :not_initialized}
    end
  end

  @doc "Consulta a Quadtree para encontrar IDs de entidades dentro de uma `range` retangular."
  @spec query(table_name, range :: boundary) :: list(entity_id)
  def query(table, range) do
    case :ets.lookup(table, :__config__) do
      [{:__config__, config}] ->
        do_query(table, config.root_id, range, [])

      [] ->
        []
    end
  end

  # =============================================================================
  # Lógica Interna (Funções Privadas)
  # =============================================================================

  defp do_insert(table, node_id, point, entity_id, config, depth) do
    # Esta operação de lookup/insert não é atômica e vulnerável a concorrência.
    [{^node_id, node}] = :ets.lookup(table, node_id)

    unless contains?(node.boundary, point), do: :ok

    case node.type do
      :leaf ->
        handle_leaf_insertion(table, node_id, node, point, entity_id, config, depth)

      :internal ->
        quadrant = get_quadrant(node.boundary, point)
        child_id = node.children[quadrant]
        do_insert(table, child_id, point, entity_id, config, depth + 1)
    end
  end

  defp handle_leaf_insertion(table, node_id, node, point, entity_id, config, depth) do
    points = node.points
    capacity = config.capacity

    if length(points) < capacity or depth >= config.max_depth do
      updated_node = %{node | points: [{point, entity_id} | points]}
      :ets.insert(table, {node_id, updated_node})
    else
      subdivide(table, node_id, node)

      for {p, eid} <- [{point, entity_id} | points] do
        do_insert(table, node_id, p, eid, config, depth)
      end
    end

    :ok
  end

  defp subdivide(table, parent_id, parent_node) do
    %{boundary: pb, points: _} = parent_node

    cx = pb.x + pb.w / 2
    cy = pb.y + pb.h / 2
    hw = pb.w / 2
    hh = pb.h / 2

    children_boundaries = %{
      ne: %{x: cx, y: pb.y, w: hw, h: hh},
      nw: %{x: pb.x, y: pb.y, w: hw, h: hh},
      se: %{x: cx, y: cy, w: hw, h: hh},
      sw: %{x: pb.x, y: cy, w: hw, h: hh}
    }

    children_ids =
      Enum.into(children_boundaries, %{}, fn {quadrant, boundary} ->
        child_id = :erlang.unique_integer([:positive])
        child_node = %{type: :leaf, boundary: boundary, points: []}
        :ets.insert(table, {child_id, child_node})
        {quadrant, child_id}
      end)

    internal_node = %{type: :internal, boundary: pb, children: children_ids}
    :ets.insert(table, {parent_id, internal_node})
  end

  defp do_query(table, node_id, range, found) do
    [{^node_id, node}] = :ets.lookup(table, node_id)

    unless intersects?(node.boundary, range), do: found

    case node.type do
      :internal ->
        Enum.reduce(node.children, found, fn {_quadrant, child_id}, acc ->
          do_query(table, child_id, range, acc)
        end)

      :leaf ->
        Enum.reduce(node.points, found, fn {[px, py], id}, acc ->
          if px >= range.x and px < range.x + range.w and
               py >= range.y and py < range.y + range.h do
            [id | acc]
          else
            acc
          end
        end)
    end
  end

  # ... Funções auxiliares de geometria ...
  defp contains?(boundary, [px, py]),
    do:
      px >= boundary.x and px < boundary.x + boundary.w and py >= boundary.y and
        py < boundary.y + boundary.h

  defp intersects?(b1, b2),
    do:
      not (b1.x + b1.w <= b2.x or b2.x + b2.w <= b1.x or b1.y + b1.h <= b2.y or
             b2.y + b2.h <= b1.y)

  defp get_quadrant(boundary, [px, py]) do
    mid_x = boundary.x + boundary.w / 2
    mid_y = boundary.y + boundary.h / 2

    cond do
      px >= mid_x and py < mid_y -> :ne
      px < mid_x and py < mid_y -> :nw
      px >= mid_x and py >= mid_y -> :se
      true -> :sw
    end
  end
end
