defmodule SnookerGameEx.Quadtree do
  @moduledoc """
  A Quadtree implementation for 2D spatial partitioning.

  This data structure is used to efficiently query for objects within a specific
  area, which is crucial for optimizing collision detection in the physics engine.
  It works by recursively subdividing a 2D space into four quadrants.

  This version assumes it is managed by a single process (like the `CollisionEngine`
  GenServer) to handle concurrency control externally. The functions are designed
  to operate on an ETS table.
  """

  @typedoc "The name of the ETS table used to store the Quadtree."
  @type table_name :: atom()
  @typedoc "A 2D point, represented as a tuple."
  @type point :: {float(), float()}
  @typedoc "A rectangular boundary."
  @type boundary :: %{x: float(), y: float(), w: float(), h: float()}
  @typedoc "The unique identifier for an entity stored in the tree."
  @type entity_id :: any()
  @typedoc "The unique identifier for a node within the tree."
  @type node_id :: integer()

  # =============================================================================
  # Public API
  # =============================================================================

  @doc "Creates and initializes the ETS table for the Quadtree."
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
      # Disabled to enforce single-process usage for writes
      write_concurrency: false
    ])

    root_id = 1
    root_node = %{type: :leaf, boundary: boundary, points: []}

    # Store the configuration for use in `clear/1`.
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

  @doc "Clears all points from the Quadtree, resetting it to its initial state."
  @spec clear(table_name) :: :ok
  def clear(table) do
    # This robust clear logic ensures the table is reset correctly.
    case :ets.lookup(table, :__config__) do
      [{:__config__, config}] ->
        # Delete only the nodes (integer keys), preserving the :__config__ record.
        match_spec = [{{:"$1", :_}, [{:is_integer, :"$1"}], [true]}]
        :ets.match_delete(table, match_spec)

        # Recreate the root node using the boundary stored in the config.
        root_id = config.root_id
        root_node = %{type: :leaf, boundary: config.boundary, points: []}
        :ets.insert(table, {root_id, root_node})
        :ok

      [] ->
        # Table might already be cleared or uninitialized.
        :ok
    end
  end

  @doc "Completely deletes the Quadtree's ETS table."
  @spec delete_table(table_name) :: :ok
  def delete_table(table), do: :ets.delete(table)

  @doc "Inserts an entity with a point and an ID into the Quadtree."
  @spec insert(table_name, point, entity_id) :: :ok | {:error, atom}
  def insert(table, point, id) do
    case :ets.lookup(table, :__config__) do
      [{:__config__, config}] ->
        do_insert(table, config.root_id, point, id, config, 0)

      [] ->
        {:error, :not_initialized}
    end
  end

  @doc "Queries the Quadtree to find IDs of entities within a rectangular `range`."
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
  # Internal Logic
  # These functions are now public to allow for detailed documentation as requested,
  # but they are designed for internal, recursive use.
  # =============================================================================

  @doc """
  The internal recursive function for inserting a point.

  It traverses the tree to find the correct leaf node for the new point.
  If the leaf is full, it triggers a subdivision.
  """
  @spec do_insert(table_name, node_id, point, entity_id, map, integer) :: :ok
  def do_insert(table, node_id, point, entity_id, config, depth) do
    # This lookup/insert operation is not atomic and is vulnerable to race conditions
    # if not managed by a single process.
    [{^node_id, node}] = :ets.lookup(table, node_id)

    # Do not insert if the point is outside the node's boundary.
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

  @doc """
  Handles the logic for inserting a point into a leaf node.

  If the leaf has space, it adds the point. If the leaf is full and the max depth
  has not been reached, it subdivides the leaf and re-inserts all points.
  """
  @spec handle_leaf_insertion(table_name, node_id, map, point, entity_id, map, integer) :: :ok
  def handle_leaf_insertion(table, node_id, node, point, entity_id, config, depth) do
    points = node.points
    capacity = config.capacity
    max_depth = config.max_depth

    if length(points) < capacity or depth >= max_depth do
      # Add the new point to the leaf
      updated_node = %{node | points: [{point, entity_id} | points]}
      :ets.insert(table, {node_id, updated_node})
    else
      # Subdivide the leaf and re-insert all points (including the new one)
      subdivide(table, node_id, node)

      for {p, eid} <- [{point, entity_id} | points] do
        do_insert(table, node_id, p, eid, config, depth)
      end
    end

    :ok
  end

  @doc "Subdivides a leaf node into four new child leaves."
  @spec subdivide(table_name, node_id, map) :: :ok
  def subdivide(table, parent_id, parent_node) do
    %{boundary: pb} = parent_node

    cx = pb.x + pb.w / 2
    cy = pb.y + pb.h / 2
    hw = pb.w / 2
    hh = pb.h / 2

    children_boundaries = %{
      ne: %{x: cx, y: pb.y, w: hw, h: hh}, # Northeast
      nw: %{x: pb.x, y: pb.y, w: hw, h: hh}, # Northwest
      se: %{x: cx, y: cy, w: hw, h: hh}, # Southeast
      sw: %{x: pb.x, y: cy, w: hw, h: hh}  # Southwest
    }

    # Create new ETS records for each child node
    children_ids =
      Enum.into(children_boundaries, %{}, fn {quadrant, boundary} ->
        child_id = :erlang.unique_integer([:positive])
        child_node = %{type: :leaf, boundary: boundary, points: []}
        :ets.insert(table, {child_id, child_node})
        {quadrant, child_id}
      end)

    # Convert the old leaf node into an internal node that points to its new children
    internal_node = %{type: :internal, boundary: pb, children: children_ids}
    :ets.insert(table, {parent_id, internal_node})
    :ok
  end

  @doc "The internal recursive function for querying a range."
  @spec do_query(table_name, node_id, boundary, list) :: list(entity_id)
  def do_query(table, node_id, range, found) do
    [{^node_id, node}] = :ets.lookup(table, node_id)

    # If the node's boundary does not intersect the query range, prune this branch.
    unless intersects?(node.boundary, range), do: found

    case node.type do
      :internal ->
        # Recursively query all children.
        Enum.reduce(node.children, found, fn {_quadrant, child_id}, acc ->
          do_query(table, child_id, range, acc)
        end)

      :leaf ->
        # Check all points in the leaf to see if they are within the range.
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

  # --- Private Geometry Helper Functions ---
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
