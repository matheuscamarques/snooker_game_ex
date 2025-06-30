defmodule SnookerGameEx.Engine.Quadtree do
  @moduledoc """
  Uma implementação de Quadtree para particionamento espacial 2D.

  Esta estrutura de dados é usada para consultar eficientemente objetos dentro de
  uma área específica, o que é crucial para otimizar a detecção de colisões.

  Esta versão foi refatorada para operar sobre uma referência de tabela ETS (`table_ref`)
  fornecida externamente. O processo que chama este módulo é responsável por
  criar (`:ets.new/2`) e destruir (`:ets.delete/1`) a tabela, garantindo o
  isolamento de recursos e evitando conflitos de nome.
  """

  @typedoc "A referência (TID) para a tabela ETS que armazena o Quadtree."
  @type table_ref :: :ets.table()
  @typedoc "Um ponto 2D, representado como uma lista de dois floats."
  @type point :: [float()]
  @typedoc "Um limite retangular."
  @type boundary :: %{x: float(), y: float(), w: float(), h: float()}
  @typedoc "O identificador único para uma entidade armazenada na árvore."
  @type entity_id :: any()
  @typedoc "O identificador único para um nó dentro da árvore."
  @type node_id :: integer()

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Inicializa a estrutura do Quadtree dentro de uma tabela ETS existente.

  Insere a configuração e o nó raiz na tabela fornecida.
  A tabela deve ser criada pelo chamador com `:ets.new/2`.
  """
  @spec initialize(
          table_ref,
          boundary,
          capacity :: non_neg_integer(),
          max_depth :: non_neg_integer()
        ) :: :ok
  def initialize(table_ref, boundary, capacity, max_depth) do
    root_id = 1
    root_node = %{type: :leaf, boundary: boundary, points: []}

    # Armazena a configuração para uso posterior, como em `clear/1`.
    config = %{
      root_id: root_id,
      capacity: capacity,
      max_depth: max_depth,
      boundary: boundary
    }

    :ets.insert(table_ref, {:__config__, config})
    :ets.insert(table_ref, {root_id, root_node})
    :ok
  end

  @doc "Limpa todos os pontos do Quadtree, redefinindo-o para seu estado inicial."
  @spec clear(table_ref) :: :ok
  def clear(table_ref) do
    case :ets.lookup(table_ref, :__config__) do
      [{:__config__, config}] ->
        # A forma mais robusta e simples de limpar a tabela é apagar tudo
        # e depois reinserir a configuração e o nó raiz.
        :ets.delete_all_objects(table_ref)

        # Reinserir a configuração que foi lida antes de apagar.
        :ets.insert(table_ref, {:__config__, config})

        # Recriar o nó raiz usando o limite armazenado na configuração.
        root_id = config.root_id
        root_node = %{type: :leaf, boundary: config.boundary, points: []}
        :ets.insert(table_ref, {root_id, root_node})
        :ok

      [] ->
        # A tabela pode já estar limpa ou não inicializada, então não há nada a fazer.
        :ok
    end
  end

  @doc "Insere uma entidade com um ponto e um ID no Quadtree."
  @spec insert(table_ref, point, entity_id) :: :ok | {:error, atom}
  def insert(table_ref, point, id) do
    case :ets.lookup(table_ref, :__config__) do
      [{:__config__, config}] ->
        do_insert(table_ref, config.root_id, point, id, config, 0)

      [] ->
        {:error, :not_initialized}
    end
  end

  @doc "Consulta o Quadtree para encontrar IDs de entidades dentro de um `range` retangular."
  @spec query(table_ref, range :: boundary) :: list(entity_id)
  def query(table_ref, range) do
    case :ets.lookup(table_ref, :__config__) do
      [{:__config__, config}] ->
        do_query(table_ref, config.root_id, range, [])

      [] ->
        []
    end
  end

  # =============================================================================
  # Lógica Interna
  # =============================================================================

  @doc false
  # MUDANÇA: Aceita uma referência de tabela (TID) em vez de um nome.
  def do_insert(table_ref, node_id, point, entity_id, config, depth) do
    [{^node_id, node}] = :ets.lookup(table_ref, node_id)

    unless contains?(node.boundary, point), do: :ok

    case node.type do
      :leaf ->
        handle_leaf_insertion(table_ref, node_id, node, point, entity_id, config, depth)

      :internal ->
        quadrant = get_quadrant(node.boundary, point)
        child_id = node.children[quadrant]
        do_insert(table_ref, child_id, point, entity_id, config, depth + 1)
    end
  end

  @doc false
  # MUDANÇA: Aceita uma referência de tabela (TID) em vez de um nome.
  def handle_leaf_insertion(table_ref, node_id, node, point, entity_id, config, depth) do
    points = node.points
    capacity = config.capacity
    max_depth = config.max_depth

    if length(points) < capacity or depth >= max_depth do
      updated_node = %{node | points: [{point, entity_id} | points]}
      :ets.insert(table_ref, {node_id, updated_node})
    else
      subdivide(table_ref, node_id, node)

      for {p, eid} <- [{point, entity_id} | points] do
        do_insert(table_ref, node_id, p, eid, config, depth)
      end
    end

    :ok
  end

  @doc false
  # MUDANÇA: Aceita uma referência de tabela (TID) em vez de um nome.
  def subdivide(table_ref, parent_id, parent_node) do
    %{boundary: pb} = parent_node
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
        :ets.insert(table_ref, {child_id, child_node})
        {quadrant, child_id}
      end)

    internal_node = %{type: :internal, boundary: pb, children: children_ids}
    :ets.insert(table_ref, {parent_id, internal_node})
    :ok
  end

  @doc false
  # MUDANÇA: Aceita uma referência de tabela (TID) em vez de um nome.
  def do_query(table_ref, node_id, range, found) do
    [{^node_id, node}] = :ets.lookup(table_ref, node_id)

    unless intersects?(node.boundary, range), do: found

    case node.type do
      :internal ->
        Enum.reduce(node.children, found, fn {_quadrant, child_id}, acc ->
          do_query(table_ref, child_id, range, acc)
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

  # --- Funções Auxiliares de Geometria (Privadas) ---
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
