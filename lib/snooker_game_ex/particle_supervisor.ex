defmodule SnookerGameEx.ParticleSupervisor do
  @moduledoc """
  Supervisor dinâmico responsável por iniciar e gerenciar o ciclo de vida dos
  processos `Particle`.
  """
  use Supervisor

  @ball_colors List.duplicate("red", 15)
  @spacing_buffer 2.5

  @doc "Inicia o supervisor de partículas."
  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Callback de inicialização do supervisor. Gera as especificações dos filhos (workers)
  para cada `Particle` a ser criada.
  """
  @impl true
  def init(_init_arg) do
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

    # --- INÍCIO DA CORREÇÃO ---
    # Calcula a coordenada Y central da mesa, considerando o deslocamento da borda.
    center_y = bounds.y + bounds.h / 2

    # Posição da bola branca. O "200" é uma distância da borda esquerda da área de jogo.
    white_ball_pos = [bounds.x + 200, center_y]

    # Posição da bola da frente do triângulo (o ápice).
    # O "700" é uma distância da borda esquerda da área de jogo.
    apex_pos = %{x: bounds.x + 700, y: center_y}
    # --- FIM DA CORREÇÃO ---

    row_separation = radius * :math.sqrt(3) + @spacing_buffer
    vertical_separation = diameter + @spacing_buffer

    triangle_positions =
      Stream.unfold(0, fn row_index ->
        num_balls_in_row = row_index + 1
        row_x = apex_pos.x + row_index * row_separation

        # Esta lógica para centralizar as fileiras do triângulo já está correta,
        # pois se baseia na posição do ápice (apex_pos), que agora foi corrigida.
        start_y = apex_pos.y - ((num_balls_in_row - 1) * vertical_separation) / 2

        positions_in_row =
          for ball_in_row_index <- 0..(num_balls_in_row - 1) do
            pos_y = start_y + ball_in_row_index * vertical_separation
            [row_x, pos_y]
          end

        {positions_in_row, row_index + 1}
      end)
      |> Stream.flat_map(& &1)
      |> Enum.take(length(@ball_colors))

    colored_balls =
      Enum.zip(@ball_colors, triangle_positions)
      |> Enum.with_index(1)
      |> Enum.map(fn {{color, pos}, id} ->
        particle_spec(id, color, pos)
      end)

    children = [
      # Bola Branca (ID 0)
      particle_spec(0, "white", white_ball_pos) # Usa a posição corrigida
      # Resto das bolas
      | colored_balls
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

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
