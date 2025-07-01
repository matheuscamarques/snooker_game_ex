# test/snooker_game_ex/engine/quadtree_test.exs

defmodule SnookerGameEx.Engine.QuadtreeTest do
  use ExUnit.Case, async: true

  alias SnookerGameEx.Engine.Quadtree

  # Função auxiliar para criar e limpar uma tabela ETS para um teste.
  defp with_table(test_function) do
    table_ref = :ets.new(:"quadtree_test_#{inspect(self())}", [:set, :public])
    # CORREÇÃO: Usamos um bloco `try/after` para garantir que :ets.delete
    # seja chamado mesmo se o teste falhar.
    try do
      test_function.(table_ref)
    after
      :ets.delete(table_ref)
    end
  end

  defp initialize_table(table_ref) do
    boundary = %{x: 0, y: 0, w: 100, h: 100}
    capacity = 4
    max_depth = 4
    Quadtree.initialize(table_ref, boundary, capacity, max_depth)
  end

  test "insert/3 insere um ponto e query/2 o encontra" do
    with_table(fn table ->
      initialize_table(table)
      assert Quadtree.insert(table, [10, 10], :entity1) == :ok
      assert Quadtree.query(table, %{x: 0, y: 0, w: 20, h: 20}) == [:entity1]
    end)
  end

  test "query/2 retorna uma lista vazia se nenhum ponto estiver no range" do
    with_table(fn table ->
      initialize_table(table)
      Quadtree.insert(table, [50, 50], :entity1)
      assert Quadtree.query(table, %{x: 0, y: 0, w: 20, h: 20}) == []
    end)
  end

  test "o quadtree se subdivide quando a capacidade é excedida" do
    with_table(fn table ->
      initialize_table(table)
      Quadtree.insert(table, [10, 10], :e1)
      Quadtree.insert(table, [11, 11], :e2)
      Quadtree.insert(table, [12, 12], :e3)
      Quadtree.insert(table, [13, 13], :e4)
      Quadtree.insert(table, [14, 14], :e5)

      results = Quadtree.query(table, %{x: 0, y: 0, w: 100, h: 100})
      assert Enum.sort(results) == [:e1, :e2, :e3, :e4, :e5]

      [{1, root_node}] = :ets.lookup(table, 1)
      assert root_node.type == :internal
    end)
  end

  test "clear/1 remove todos os pontos mas mantém a estrutura" do
    with_table(fn table ->
      initialize_table(table)
      Quadtree.insert(table, [10, 10], :e1)
      Quadtree.insert(table, [20, 20], :e2)

      assert Quadtree.clear(table) == :ok

      assert Quadtree.query(table, %{x: 0, y: 0, w: 100, h: 100}) == []

      [{1, root_node}] = :ets.lookup(table, 1)
      assert root_node.type == :leaf
      assert root_node.points == []
    end)
  end
end
