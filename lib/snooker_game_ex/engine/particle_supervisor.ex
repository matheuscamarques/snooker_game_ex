defmodule SnookerGameEx.Engine.ParticleSupervisor do
  @moduledoc "ADAPTER: Supervisor dinâmico para os processos Particle."
  use Supervisor

  alias SnookerGameEx.Engine.CollisionEngine
  alias SnookerGameEx.Engine.Particle

  @spacing_buffer 2.5
  @pool_ball_set [
    %{number: 1, type: :solid, base_color: "#fdd835"},
    %{number: 2, type: :solid, base_color: "#1e88e5"},
    %{number: 3, type: :solid, base_color: "#e53935"},
    %{number: 4, type: :solid, base_color: "#8e24aa"},
    %{number: 5, type: :solid, base_color: "#fb8c00"},
    %{number: 6, type: :solid, base_color: "#43a047"},
    %{number: 7, type: :solid, base_color: "#5d4037"},
    %{number: 8, type: :solid, base_color: "#212121"},
    %{number: 9, type: :stripe, base_color: "#fdd835"},
    %{number: 10, type: :stripe, base_color: "#1e88e5"},
    %{number: 11, type: :stripe, base_color: "#e53935"},
    %{number: 12, type: :stripe, base_color: "#8e24aa"},
    %{number: 13, type: :stripe, base_color: "#fb8c00"},
    %{number: 14, type: :stripe, base_color: "#43a047"},
    %{number: 15, type: :stripe, base_color: "#5d4037"}
  ]

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(game_id))
  end

  def via_tuple(game_id),
    do: {:via, Registry, {SnookerGameEx.GameRegistry, {__MODULE__, game_id}}}

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    ets_table = Keyword.fetch!(opts, :ets_table)
    notifier = Keyword.fetch!(opts, :notifier)

    bounds = CollisionEngine.world_bounds()
    radius = CollisionEngine.particle_radius()
    diameter = radius * 2
    center_y = bounds.y + bounds.h / 2
    white_ball_pos = [bounds.x + 200, center_y]
    apex_pos = %{x: bounds.x + 700, y: center_y}
    row_separation = radius * :math.sqrt(3) + @spacing_buffer
    vertical_separation = diameter + @spacing_buffer
    rack_balls = Enum.shuffle(@pool_ball_set)

    triangle_positions =
      Stream.unfold(0, fn
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

    colored_balls =
      Enum.zip(rack_balls, triangle_positions)
      |> Enum.with_index(1)
      |> Enum.map(fn {{ball_data, pos}, id} ->
        particle_spec(game_id, ets_table, notifier, id, ball_data, pos)
      end)

    children = [
      particle_spec(
        game_id,
        ets_table,
        notifier,
        0,
        %{number: 0, type: :cue, base_color: "white"},
        white_ball_pos
      )
      | colored_balls
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # --- CORREÇÃO PRINCIPAL AQUI ---
  # A estratégia de reinício é removida. O padrão `:transient` será usado para todas as bolas.
  # Isso é o comportamento correto, pois um processo terminado normalmente não deve ser reiniciado.
  defp particle_spec(game_id, ets_table, notifier, id, ball_data, pos) do
    %{
      id: {game_id, id},
      start: {
        Particle,
        :start_link,
        [
          [
            game_id: game_id,
            ets_table: ets_table,
            notifier: notifier,
            id: id,
            pos: pos,
            vel: [0, 0],
            radius: CollisionEngine.particle_radius(),
            mass: CollisionEngine.particle_mass(),
            color: ball_data
          ]
        ]
      },
      # Todas as bolas são transientes.
      restart: :transient,
      type: :worker
    }
  end
end
