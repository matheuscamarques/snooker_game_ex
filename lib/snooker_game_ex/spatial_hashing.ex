defmodule SnookerGameEx.SpatialHash do
  @moduledoc """
  Implementação de um `Spatial Hash`, uma estrutura de dados para otimização espacial.

  O objetivo é acelerar a busca por objetos próximos ("broad-phase" da detecção de colisão).
  O espaço 2D é dividido em uma grade de células de tamanho fixo. Cada objeto é inserido
  na célula correspondente à sua posição.

  Ao procurar por objetos próximos a um ponto, em vez de verificar todos os objetos na
  simulação, apenas consultamos as células da grade que se sobrepõem à área de busca.
  Isso reduz drasticamente a complexidade do problema de O(n²) para algo próximo a O(n).
  """

  defstruct cell_size: 100, grid: %{}

  @type t :: %__MODULE__{
          cell_size: pos_integer(),
          # A grade é um mapa onde as chaves são coordenadas de célula {x, y} e os valores
          # são `MapSet`s contendo os IDs dos objetos naquela célula.
          grid: %{optional({integer(), integer()}) => MapSet.t(any())}
        }

  @doc """
  Cria uma nova instância do `SpatialHash`.
  O `cell_size` deve ser, idealmente, um pouco maior que o tamanho dos objetos que serão inseridos.
  """
  def new(cell_size) when is_number(cell_size) and cell_size > 0 do
    %__MODULE__{cell_size: cell_size}
  end

  @doc """
  Insere um objeto (identificado por `id`) na posição `{x, y}` na grade.
  """
  def insert(%__MODULE__{cell_size: size, grid: grid} = hash, {x, y}, id) do
    # Calcula a coordenada da célula na grade dividindo a posição pelo tamanho da célula.
    cell_x = trunc(x / size)
    cell_y = trunc(y / size)
    key = {cell_x, cell_y}

    # Adiciona o ID ao MapSet da célula correspondente.
    updated_grid =
      Map.update(grid, key, MapSet.new([id]), fn set ->
        MapSet.put(set, id)
      end)

    %__MODULE__{hash | grid: updated_grid}
  end

  @doc """
  Consulta a grade e retorna uma lista de todos os IDs de objetos encontrados dentro
  do `radius` de busca a partir do ponto `{x, y}`.
  """
  def query(%__MODULE__{cell_size: size, grid: grid}, {x, y}, radius) do
    # Calcula o intervalo de células (bounding box) a ser verificado.
    min_x = trunc((x - radius) / size)
    max_x = trunc((x + radius) / size)
    min_y = trunc((y - radius) / size)
    max_y = trunc((y + radius) / size)

    # Itera sobre todas as células no bounding box e coleta todos os IDs.
    min_x..max_x
    |> Enum.flat_map(fn cx ->
      Enum.flat_map(min_y..max_y, fn cy ->
        Map.get(grid, {cx, cy}, MapSet.new()) |> MapSet.to_list()
      end)
    end)
  end
end
