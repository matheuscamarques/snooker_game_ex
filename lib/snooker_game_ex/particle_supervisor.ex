defmodule SnookerGameEx.ParticleSupervisor do
  @moduledoc """
  A dynamic supervisor responsible for starting and managing the lifecycle
  of `Particle` processes.
  """
  use Supervisor

  @spacing_buffer 2.5

  # Define the standard 8-ball pool set.
  # Number 0 is the cue ball.
  # Numbers 1-7 are solids.
  # Number 8 is the 8-ball.
  # Numbers 9-15 are stripes.
  @pool_ball_set [
    # Yellow
    %{number: 1, type: :solid, base_color: "#fdd835"},
    # Blue
    %{number: 2, type: :solid, base_color: "#1e88e5"},
    # Red
    %{number: 3, type: :solid, base_color: "#e53935"},
    # Purple
    %{number: 4, type: :solid, base_color: "#8e24aa"},
    # Orange
    %{number: 5, type: :solid, base_color: "#fb8c00"},
    # Green
    %{number: 6, type: :solid, base_color: "#43a047"},
    # Maroon/Brown
    %{number: 7, type: :solid, base_color: "#5d4037"},
    # Black
    %{number: 8, type: :solid, base_color: "#212121"},
    # Yellow Stripe
    %{number: 9, type: :stripe, base_color: "#fdd835"},
    # Blue Stripe
    %{number: 10, type: :stripe, base_color: "#1e88e5"},
    # Red Stripe
    %{number: 11, type: :stripe, base_color: "#e53935"},
    # Purple Stripe
    %{number: 12, type: :stripe, base_color: "#8e24aa"},
    # Orange Stripe
    %{number: 13, type: :stripe, base_color: "#fb8c00"},
    # Green Stripe
    %{number: 14, type: :stripe, base_color: "#43a047"},
    # Maroon/Brown Stripe
    %{number: 15, type: :stripe, base_color: "#5d4037"}
  ]

  @doc "Starts the particle supervisor."
  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

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
    center_y = bounds.y + bounds.h / 2
    white_ball_pos = [bounds.x + 200, center_y]
    apex_pos = %{x: bounds.x + 700, y: center_y}

    row_separation = radius * :math.sqrt(3) + @spacing_buffer
    vertical_separation = diameter + @spacing_buffer

    # Shuffle the pool ball set for a random rack each time.
    rack_balls = Enum.shuffle(@pool_ball_set)

    # Generates the positions for the 15 balls in the triangular rack.
    triangle_positions =
      Stream.unfold(0, fn
        # Stop after 5 rows (1+2+3+4+5 = 15 balls)
        5 ->
          nil

        row_index ->
          num_balls_in_row = row_index + 1
          row_x = apex_pos.x + row_index * row_separation
          start_y = apex_pos.y - (num_balls_in_row - 1) * vertical_separation / 2

          positions_in_row =
            for ball_in_row_index <- 0..(num_balls_in_row - 1) do
              pos_y = start_y + ball_in_row_index * vertical_separation
              [row_x, pos_y]
            end

          {positions_in_row, row_index + 1}
      end)
      |> Enum.flat_map(& &1)
      |> Enum.take(15)

    # Creates the child specs for the colored balls.
    colored_balls =
      Enum.zip(rack_balls, triangle_positions)
      # Start IDs from 1, as 0 is the white ball.
      |> Enum.with_index(1)
      |> Enum.map(fn {{ball_data, pos}, id} ->
        # Pass the entire map of ball data to the particle spec.
        particle_spec(id, ball_data, pos)
      end)

    # Combine all child specs for the supervisor.
    children = [
      # White Ball / Cue Ball (ID 0)
      particle_spec(0, %{number: 0, type: :cue, base_color: "white"}, white_ball_pos)
      # The rest of the balls
      | colored_balls
    ]

    Supervisor.init(children, strategy: :one_for_one, restart: :transient)
  end

  # --- Private Helper ---

  # The 'color' parameter is now a map containing all visual data for the ball.
  defp particle_spec(id, ball_data, pos) do
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
             # Pass the whole map
             color: ball_data
           ]
         ]},
      restart: :transient,
      type: :worker
    }
  end
end
