defmodule SnookerGameEx.SpatialHash do
  @moduledoc """
  An implementation of a `Spatial Hash`, a data structure for spatial optimization.

  The goal is to accelerate the search for nearby objects (the "broad-phase" of
  collision detection). The 2D space is divided into a grid of fixed-size cells.
  Each object is inserted into the cell corresponding to its position.

  When searching for objects near a point, instead of checking every object in the
  simulation, we only need to query the grid cells that overlap with the search area.
  This drastically reduces the problem's complexity from O(n^2) to nearly O(n).
  This implementation is in-memory, using nested maps.
  """

  defstruct cell_size: 100, grid: %{}

  @type t :: %__MODULE__{
          cell_size: pos_integer(),
          # The grid is a map where keys are cell coordinates {x, y} and values
          # are `MapSet`s containing the IDs of the objects in that cell.
          grid: %{optional({integer(), integer()}) => MapSet.t(any())}
        }

  @doc """
  Creates a new `SpatialHash` instance.

  The `cell_size` should ideally be slightly larger than the size of the
  objects that will be inserted.
  """
  @spec new(cell_size :: number()) :: t()
  def new(cell_size) when is_number(cell_size) and cell_size > 0 do
    %__MODULE__{cell_size: cell_size}
  end

  @doc """
  Inserts an object (identified by `id`) at position `{x, y}` into the grid.
  """
  @spec insert(hash :: t(), pos :: {number(), number()}, id :: any()) :: t()
  def insert(%__MODULE__{cell_size: size, grid: grid} = hash, {x, y}, id) do
    # Calculate the grid cell coordinate by dividing the position by the cell size.
    cell_x = trunc(x / size)
    cell_y = trunc(y / size)
    key = {cell_x, cell_y}

    # Add the ID to the MapSet of the corresponding cell.
    updated_grid =
      Map.update(grid, key, MapSet.new([id]), fn set ->
        MapSet.put(set, id)
      end)

    %__MODULE__{hash | grid: updated_grid}
  end

  @doc """
  Queries the grid and returns a list of all object IDs found within the
  search `radius` from the point `{x, y}`.
  """
  @spec query(hash :: t(), pos :: {number(), number()}, radius :: number()) :: list(any())
  def query(%__MODULE__{cell_size: size, grid: grid}, {x, y}, radius) do
    # Calculate the range of cells (a bounding box) to be checked.
    min_x = trunc((x - radius) / size)
    max_x = trunc((x + radius) / size)
    min_y = trunc((y - radius) / size)
    max_y = trunc((y + radius) / size)

    # Iterate over all cells in the bounding box and collect all IDs.
    min_x..max_x
    |> Enum.flat_map(fn cx ->
      Enum.flat_map(min_y..max_y, fn cy ->
        Map.get(grid, {cx, cy}, MapSet.new()) |> MapSet.to_list()
      end)
    end)
  end
end
