defmodule SnookerGameEx.SpatialHashETS do
  @moduledoc """
  An implementation of a Spatial Hash data structure using an ETS table as the backend.

  A Spatial Hash is a grid-based data structure that is very efficient for uniformally
  distributed spatial data. It works by dividing the space into a grid of cells and
  storing entities in the cells they occupy. Queries for nearby objects only need to
  check the entities in the nearby grid cells, which is very fast.

  **IMPROVEMENTS APPLIED:**
  1.  **No Compile-Time Transform:** Removed the need for complex compile-time metaprogramming.
  2.  **Safe `clear/1`:** The clear function now correctly deletes only grid data, preserving the configuration.
  3.  **Optimized Queries:** Uses a safe, dynamically generated `match_spec` for efficient ETS queries.
  4.  **Stateful `cell_size`:** The grid's `cell_size` is now stored in the table's state.
  5.  **Concurrency-Ready:** Uses `write_concurrency: true` and atomic operations suitable for concurrent access.
  """

  @type table_name :: atom()
  @type cell_key :: {integer(), integer()}
  @type particle_id :: any()

  @doc """
  Creates and initializes the ETS table for the Spatial Hash.
  """
  @spec init(table_name :: table_name(), cell_size :: pos_integer()) :: :ok
  def init(table, cell_size) when is_atom(table) and is_integer(cell_size) and cell_size > 0 do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Store the configuration in a protected tuple.
    :ets.insert(table, {:__config__, cell_size})
    :ok
  end

  @doc """
  Efficiently clears the grid of all entities, preserving the configuration.
  """
  @spec clear(table :: table_name()) :: :ok
  def clear(table) do
    # This match_spec ensures that we are only deleting tuples where the first
    # and second elements are integer cell coordinates: {cx, cy, id}.
    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [
          # Guards to ensure the type of the elements.
          {:is_integer, :"$1"},
          {:is_integer, :"$2"}
        ],
        # The result of the match (not important here).
        [true]
      }
    ]

    :ets.match_delete(table, match_spec)
    :ok
  end

  @doc """
  Converts world coordinates to grid cell coordinates.
  """
  @spec to_cell_coords({x :: float(), y :: float()}, cell_size :: pos_integer()) :: cell_key
  defp to_cell_coords({x, y}, cell_size) do
    {div(floor(x), cell_size), div(floor(y), cell_size)}
  end

  @doc """
  Inserts a particle into the ETS grid.
  """
  @spec insert(
          table :: table_name(),
          pos :: {float(), float()},
          id :: particle_id(),
          cell_size :: pos_integer()
        ) :: :ok
  def insert(table, {x, y}, id, cell_size) do
    {cx, cy} = to_cell_coords({x, y}, cell_size)
    :ets.insert(table, {cx, cy, id})
    :ok
  end

  @doc """
  Queries the grid to find particle IDs within a given search radius.
  """
  @spec query(
          table :: table_name(),
          pos :: {float(), float()},
          radius :: float(),
          cell_size :: pos_integer()
        ) :: list(particle_id())
  def query(table, {x, y}, radius, cell_size) do
    # Safely calculate the boundary of the query area in world coordinates.
    min_x = floor(x - radius)
    max_x = floor(x + radius)
    min_y = floor(y - radius)
    max_y = floor(y + radius)

    # Convert the world boundary to a grid cell boundary.
    min_cx = div(min_x, cell_size)
    max_cx = div(max_x, cell_size)
    min_cy = div(min_y, cell_size)
    max_cy = div(max_y, cell_size)

    # Generate a match_spec to select all entities within the cell boundary.
    # This is much more efficient than fetching all records and filtering in Elixir.
    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [
          {:andalso, {:>=, :"$1", min_cx},
           {:andalso, {:"=<", :"$1", max_cx},
            {:andalso, {:>=, :"$2", min_cy}, {:"=<", :"$2", max_cy}}}}
        ],
        # Return only the third element of the tuple (the particle ID).
        [:"$3"]
      }
    ]

    :ets.select(table, match_spec)
  end
end
