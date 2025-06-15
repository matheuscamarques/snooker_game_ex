defmodule SnookerGameEx.SpatialHash do
  @moduledoc """
  Uma implementação de Spatial Hash Grid usando uma tabela ETS.

  Esta estrutura de dados divide o espaço 2D em uma grade de células de tamanho
  uniforme. As entidades são inseridas nas células que elas sobrepõem. Para
  consultar vizinhos próximos, verificamos apenas as células que a área de
  interesse sobrepõe, otimizando significativamente a detecção de colisões.

  A chave na tabela ETS é a coordenada da célula (ex: `{10, 5}`), e o valor é o
  ID da entidade. Usamos uma tabela do tipo `:duplicate_bag` para permitir que
  múltiplas entidades existam na mesma célula.
  """
  defmodule Envelope do
    @moduledoc """
    Defines a simple bounding box (envelope).
    """
    defstruct [:min_x, :min_y, :max_x, :max_y]

    # Helper function para criar um envelope a partir de um centro e raio
    def from_particle(pos, radius) do
      [px, py] = pos

      %__MODULE__{
        min_x: px - radius,
        min_y: py - radius,
        max_x: px + radius,
        max_y: py + radius
      }
    end
  end

  @typedoc "O nome da tabela ETS."
  @type table_name :: atom()
  @typedoc "Um ponto 2D."
  @type point :: [float()]
  @typedoc "Uma caixa delimitadora (Axis-Aligned Bounding Box)."
  @type envelope :: %Envelope{}
  @typedoc "Os limites do mundo."
  @type boundary :: %{x: float(), y: float(), w: float(), h: float()}
  @typedoc "O ID único de uma entidade."
  @type entity_id :: any()

  defmodule Envelope do
    @moduledoc "Define uma caixa delimitadora simples (envelope ou AABB)."
    defstruct [:min_x, :min_y, :max_x, :max_y]

    @doc "Cria um envelope a partir da posição e raio de uma partícula."
    def from_particle([px, py], radius) do
      %__MODULE__{
        min_x: px - radius,
        min_y: py - radius,
        max_x: px + radius,
        max_y: py + radius
      }
    end
  end

  # =============================================================================
  # API Pública
  # =============================================================================

  @doc "Cria e inicializa a tabela ETS para o Spatial Hash."
  @spec init(table_name, boundary, cell_size :: number) :: :ok
  def init(table, bounds, cell_size) do
    :ets.new(table, [
      :duplicate_bag,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: false
    ])

    # Armazena a configuração para uso posterior nas funções de hash
    config = %{bounds: bounds, cell_size: cell_size}
    :ets.insert(table, {:__config__, config})

    :ok
  end

  @doc "Remove todas as entidades da grade, mantendo a configuração."
  @spec clear(table_name) :: :ok
  def clear(table) do
    # Deleta todos os objetos exceto a tupla de configuração
    match_spec = [{{:"$1", :_}, [{:"/=", :"$1", :__config__}], [true]}]
    :ets.match_delete(table, match_spec)
    :ok
  end

  @doc "Insere uma entidade na grade."
  @spec insert(table_name, entity_id, point, radius :: number) :: :ok
  def insert(table, entity_id, pos, radius) do
    [{:__config__, config}] = :ets.lookup(table, :__config__)
    envelope = Envelope.from_particle(pos, radius)
    {x_range, y_range} = get_cell_range(envelope, config)

    # Insere o ID da entidade em cada célula da grade que ela sobrepõe
    for cx <- x_range, cy <- y_range do
      :ets.insert(table, {{cx, cy}, entity_id})
    end

    :ok
  end

  @doc "Consulta a grade para encontrar IDs de entidades em uma determinada área."
  @spec query(table_name, point, radius :: number) :: list(entity_id)
  def query(table, pos, radius) do
    [{:__config__, config}] = :ets.lookup(table, :__config__)
    envelope = Envelope.from_particle(pos, radius)
    {x_range, y_range} = get_cell_range(envelope, config)

    # Coleta os IDs de todas as células sobrepostas
    ids =
      for cx <- x_range, cy <- y_range do
        :ets.lookup_element(table, {cx, cy}, 2)
      end

    # Aplana a lista de listas e remove duplicatas
    ids
    |> List.flatten()
    |> Enum.uniq()
  end

  # =============================================================================
  # Funções Auxiliares Internas
  # =============================================================================

  @doc "Calcula o intervalo de coordenadas de células que um envelope sobrepõe."
  @spec get_cell_range(envelope, map) :: {%Range{}, %Range{}}
  defp get_cell_range(envelope, config) do
    %{bounds: bounds, cell_size: cell_size} = config

    min_cx = get_cell_coord(envelope.min_x, bounds.x, cell_size)
    max_cx = get_cell_coord(envelope.max_x, bounds.x, cell_size)
    min_cy = get_cell_coord(envelope.min_y, bounds.y, cell_size)
    max_cy = get_cell_coord(envelope.max_y, bounds.y, cell_size)

    {min_cx..max_cx, min_cy..max_cy}
  end

  @doc "Converte uma coordenada do mundo para uma coordenada da grade."
  @spec get_cell_coord(number, number, number) :: integer
  defp get_cell_coord(pos, origin, cell_size) do
    floor((pos - origin) / cell_size)
  end
end
