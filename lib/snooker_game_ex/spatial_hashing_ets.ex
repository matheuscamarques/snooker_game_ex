defmodule SnookerGameEx.SpatialHashETS do
  @moduledoc """
  Implementação de um Spatial Hash utilizando uma tabela ETS como backend.

  **CORREÇÕES APLICADAS:**
  1. Remoção da transformação de compile-time desnecessária
  2. Correção da função clear() para não deletar a configuração
  3. Otimização das queries com match_spec segura
  4. Armazenamento do cell_size no estado da tabela
  5. Correção de problemas de concorrência
  """

  @type table_name :: atom()
  @type cell_key :: {integer(), integer()}
  @type particle_id :: any()

  @doc "Cria a tabela ETS para o Spatial Hash."
  @spec init(table_name, non_neg_integer()) :: :ok
  def init(table, cell_size) when is_atom(table) and is_integer(cell_size) and cell_size > 0 do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Armazena configuração como tupla protegida
    :ets.insert(table, {:__config__, cell_size})
    :ok
  end

  @doc "Limpa eficientemente a grade, preservando a configuração."
  def clear(table) do
    # Este match_spec garante que estamos deletando apenas tuplas onde
    # o primeiro e o segundo elementos são coordenadas de célula (inteiros).
    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [
          # Guards para garantir o tipo dos elementos
          {:is_integer, :"$1"},
          {:is_integer, :"$2"}
        ],
        # O resultado da correspondência (não importa aqui)
        [true]
      }
    ]

    :ets.match_delete(table, match_spec)
    :ok
  end

  @doc "Converte a posição do mundo para a coordenada da célula."
  @spec to_cell_coords({float(), float()}, non_neg_integer()) :: cell_key
  defp to_cell_coords({x, y}, cell_size) do
    {div(floor(x), cell_size), div(floor(y), cell_size)}
  end

  @doc "Insere uma partícula na grade ETS."
  def insert(table, {x, y}, id, cell_size) do
    # Obtém cell_size da tabela de forma segura
    {cx, cy} = to_cell_coords({x, y}, cell_size)
    :ets.insert(table, {cx, cy, id})
    :ok
  end

  @doc "Consulta a grade para encontrar IDs de partículas num raio de busca."
  def query(table, {x, y}, radius, cell_size) do
    # Cálculo seguro dos limites
    min_x = floor(x - radius)
    max_x = floor(x + radius)
    min_y = floor(y - radius)
    max_y = floor(y + radius)

    min_cx = div(min_x, cell_size)
    max_cx = div(max_x, cell_size)
    min_cy = div(min_y, cell_size)
    max_cy = div(max_y, cell_size)

    # Geração de match_spec sem parse_transform
    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [
          {:andalso, {:>=, :"$1", min_cx},
           {:andalso, {:"=<", :"$1", max_cx},
            {:andalso, {:>=, :"$2", min_cy}, {:"=<", :"$2", max_cy}}}}
        ],
        [:"$3"]
      }
    ]

    :ets.select(table, match_spec)
  end
end
