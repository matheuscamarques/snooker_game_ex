defmodule SnookerGameEx.ParticleSupervisor do
  @moduledoc """
  A dynamic supervisor responsible for starting and managing the lifecycle
  of `Particle` processes for a specific game instance.
  """
  use Supervisor

  @spacing_buffer 2.5

  # Define o conjunto padrão de bolas de sinuca (8-ball).
  @pool_ball_set [
    # Amarela
    %{number: 1, type: :solid, base_color: "#fdd835"},
    # Azul
    %{number: 2, type: :solid, base_color: "#1e88e5"},
    # Vermelha
    %{number: 3, type: :solid, base_color: "#e53935"},
    # Roxa
    %{number: 4, type: :solid, base_color: "#8e24aa"},
    # Laranja
    %{number: 5, type: :solid, base_color: "#fb8c00"},
    # Verde
    %{number: 6, type: :solid, base_color: "#43a047"},
    # Marrom
    %{number: 7, type: :solid, base_color: "#5d4037"},
    # Preta
    %{number: 8, type: :solid, base_color: "#212121"},
    # Amarela Listrada
    %{number: 9, type: :stripe, base_color: "#fdd835"},
    # Azul Listrada
    %{number: 10, type: :stripe, base_color: "#1e88e5"},
    # Vermelha Listrada
    %{number: 11, type: :stripe, base_color: "#e53935"},
    # Roxa Listrada
    %{number: 12, type: :stripe, base_color: "#8e24aa"},
    # Laranja Listrada
    %{number: 13, type: :stripe, base_color: "#fb8c00"},
    # Verde Listrada
    %{number: 14, type: :stripe, base_color: "#43a047"},
    # Marrom Listrada
    %{number: 15, type: :stripe, base_color: "#5d4037"}
  ]

  @doc "Inicia o supervisor de partículas para um jogo específico."
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

    # CORREÇÃO: Removida a chamada para maybe_create_ets_table().
    # A tabela ETS agora é criada pelo GameInstanceSupervisor com um nome
    # específico para o jogo e passada para este módulo via `opts`.

    bounds = SnookerGameEx.CollisionEngine.world_bounds()
    radius = SnookerGameEx.CollisionEngine.particle_radius()
    diameter = radius * 2

    # --- Posicionamento Inicial das Bolas ---
    center_y = bounds.y + bounds.h / 2
    white_ball_pos = [bounds.x + 200, center_y]
    apex_pos = %{x: bounds.x + 700, y: center_y}

    row_separation = radius * :math.sqrt(3) + @spacing_buffer
    vertical_separation = diameter + @spacing_buffer

    # Embaralha o conjunto de bolas para uma organização aleatória a cada vez.
    rack_balls = Enum.shuffle(@pool_ball_set)

    # Gera as posições para as 15 bolas no triângulo.
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

    # CORREÇÃO: A lógica para criar os `children` foi simplificada e corrigida
    # para passar todos os argumentos necessários (`game_id`, `ets_table`, etc.)
    # para a função `particle_spec`.

    # Cria as especificações dos filhos para as bolas coloridas.
    colored_balls =
      Enum.zip(rack_balls, triangle_positions)
      # IDs começam em 1, já que 0 é a bola branca.
      |> Enum.with_index(1)
      |> Enum.map(fn {{ball_data, pos}, id} ->
        # Passa todos os dados necessários para a especificação da partícula.
        particle_spec(game_id, ets_table, id, ball_data, pos)
      end)

    # Combina todas as especificações dos filhos para o supervisor.
    children = [
      # Bola Branca (ID 0)
      particle_spec(
        game_id,
        ets_table,
        0,
        %{number: 0, type: :cue, base_color: "white"},
        white_ball_pos
      )
      # O resto das bolas
      | colored_balls
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # CORREÇÃO: A função `maybe_create_ets_table` foi removida completamente.
  # Ela não é mais necessária, pois a tabela ETS é gerenciada pelo
  # GameInstanceSupervisor.

  # --- Função Auxiliar Privada ---

  defp particle_spec(game_id, ets_table, id, ball_data, pos) do
    %{
      # O ID do filho para o supervisor deve ser único. Uma tupla com game_id e id da bola funciona bem.
      id: {game_id, id},
      start:
        {SnookerGameEx.Particle, :start_link,
         [
           # CORREÇÃO: Adicionado `ets_table: ets_table` à lista de opções.
           # O processo Particle precisa saber qual tabela ETS usar.
           [
             game_id: game_id,
             ets_table: ets_table,
             id: id,
             pos: pos,
             vel: [0, 0],
             radius: SnookerGameEx.CollisionEngine.particle_radius(),
             mass: SnookerGameEx.CollisionEngine.particle_mass(),
             color: ball_data
           ]
         ]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Reinicia a instância de jogo associada, colocando todas as partículas
  em seus estados iniciais.
  """
  def restart(game_id) do
    # A lógica de reinicialização foi movida para o GameInstanceSupervisor (ou similar).
    # Esta chamada está correta se CollisionEngine.restart/1 lida com o reinício
    # da árvore de supervisão do jogo.
    SnookerGameEx.CollisionEngine.restart(game_id)
  end
end
