defmodule SnookerGameEx.ParticleSupervisor do
  @moduledoc """
  A dynamic supervisor responsible for starting and managing the lifecycle
  of `Particle` processes.
  """
  use Supervisor

  @ball_colors List.duplicate("red", 15)
  @spacing_buffer 2.5

  @doc "Starts the particle supervisor."
  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  The supervisor's init callback.

  It generates the child specifications (workers) for each `Particle` to be created,
  placing them in their initial positions on the snooker table (the white ball and
  the triangular rack of red balls). It also creates the `:particle_data` ETS
  table that will be shared across processes.
  """
  @impl true
  def init(_init_arg) do
    # Creates the ETS table that will store all particle state data for quick access.
    :ets.new(:particle_data, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    bounds = SnookerGameEx.CollisionEngine.world_bounds()
    radius = SnookerGameEx.CollisionEngine.particle_radius()
    diameter = radius * 2

    # --- Initial Ball Positioning ---
    # Calculate the center Y coordinate of the table, accounting for the border offset.
    center_y = bounds.y + bounds.h / 2

    # Position of the white ball. "200" is a distance from the left edge of the play area.
    white_ball_pos = [bounds.x + 200, center_y]

    # Position of the front ball of the triangle (the apex).
    # "700" is a distance from the left edge of the play area.
    apex_pos = %{x: bounds.x + 700, y: center_y}

    # Calculate the separation distances for the triangular rack.
    row_separation = radius * :math.sqrt(3) + @spacing_buffer
    vertical_separation = diameter + @spacing_buffer

    # Generates the positions for the balls in the triangular rack.
    triangle_positions =
      Stream.unfold(0, fn row_index ->
        num_balls_in_row = row_index + 1
        row_x = apex_pos.x + row_index * row_separation

        # This logic correctly centers the rows of the triangle
        # based on the apex position.
        start_y = apex_pos.y - (num_balls_in_row - 1) * vertical_separation / 2

        positions_in_row =
          for ball_in_row_index <- 0..(num_balls_in_row - 1) do
            pos_y = start_y + ball_in_row_index * vertical_separation
            [row_x, pos_y]
          end

        {positions_in_row, row_index + 1}
      end)
      |> Stream.flat_map(& &1)
      |> Enum.take(length(@ball_colors))

    # Creates the child specs for the colored balls.
    colored_balls =
      Enum.zip(@ball_colors, triangle_positions)
      |> Enum.with_index(1)
      |> Enum.map(fn {{color, pos}, id} ->
        particle_spec(id, color, pos)
      end)

    # Combine all child specs for the supervisor.
    children = [
      # White Ball (ID 0)
      particle_spec(0, "white", white_ball_pos)
      # The rest of the balls
      | colored_balls
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # --- Private Helper ---

  # Generates a supervisor child specification for a single particle.
  defp particle_spec(id, color, pos) do
    %{
      id: id,
      start:
        {SnookerGameEx.Particle, :start_link,
         [
           [
             id: id,
             pos: pos,
             vel: [0, 0],
             radius: SnookerGameEx.CollisionEngine.particle_radius(),
             mass: SnookerGameEx.CollisionEngine.particle_mass(),
             color: color
           ]
         ]},
      restart: :permanent,
      type: :worker
    }
  end
end
