defmodule AstarTest do
  use ExUnit.Case
  doctest Astar
  require Graph
  require GraphNode

  test "can navigate between two connected nodes" do
    graph  = %Graph{}
    node_a = %GraphNode{ name: :a, entity: %{} }
    node_b = %GraphNode{ name: :b, entity: %{} }

    {graph, _, _} = graph |> Graph.add_edge(node_a, node_b, 1)

    assert [node_b] == Astar.find_path(node_a, graph, node_b)
  end

  test "can navigate between three connected nodes" do
    graph  = %Graph{}
    node_a = %GraphNode{ name: :a, entity: %{ x: 0, y:  0 } }
    node_b = %GraphNode{ name: :b, entity: %{ x: 0, y: 10 } }
    node_c = %GraphNode{ name: :c, entity: %{ x: 0, y: 30 } }

    {graph, node_a, node_b} = graph |> Graph.add_edge(node_a, node_b, 10)
    {graph, node_b, node_c} = graph |> Graph.add_edge(node_b, node_c, 20)

    assert [node_b.name, node_c.name] == Astar.find_path(node_a, graph, node_c) |> Enum.map(fn(node) -> node.name end)
  end

  test "can navigate a graph of nodes" do
    graph  = %Graph{}
    node_a = %GraphNode{ name: :a, entity: %{ x:  0.0, y:  0.0 } }
    node_b = %GraphNode{ name: :b, entity: %{ x:  0.0, y: 10.0 } }
    node_c = %GraphNode{ name: :c, entity: %{ x: 10.0, y: 10.0 } }
    node_d = %GraphNode{ name: :d, entity: %{ x: 10.0, y:  3.0 } }

    {graph, node_a, node_b} = graph |> Graph.add_edge(node_a, node_b, 10.0)
    {graph, node_a, node_c} = graph |> Graph.add_edge(node_a, node_c, 14.4)
    {graph, node_b, node_c} = graph |> Graph.add_edge(node_b, node_c, 10.0)
    {graph, node_b, node_d} = graph |> Graph.add_edge(node_b, node_d,  3.0)
    {graph,      _, node_d} = graph |> Graph.add_edge(node_c, node_d,  7.0)

    assert [node_b, node_d] == Astar.find_path(node_a, graph, node_d)
  end

  test "can add new points to a pre-built graph" do
    graph = %Graph{}
    a = %Planet{ id: 0, x:  0.0, y:  0.0, radius: 2.0 }
    b = %Planet{ id: 1, x:  0.0, y: 10.0, radius: 2.0 }
    c = %Planet{ id: 2, x: 10.0, y: 10.0, radius: 2.0 }
    d = %Planet{ id: 3, x: 20.0, y: 20.0, radius: 2.0 }
    start_point = %Ship{ id: 0, x: -10.0, y: -10.0, radius: 0.5 }
    end_point   = %Ship{ id: 1, x:  13.0, y:  13.0, radius: 0.5 }

    map = %GameMap{ planets: %{"0": a, "1": b, "2": c, "3": d} }
    graph = GameMap.planet_graph(map)

    node_a = Graph.get_node(graph, Entity.to_atom(a))
    node_b = Graph.get_node(graph, Entity.to_atom(b))
    node_c = Graph.get_node(graph, Entity.to_atom(c))
    node_d = Graph.get_node(graph, Entity.to_atom(d))

    assert_adjacents node_a, [b, c]
    assert_adjacents node_b, [a, c, d]
    assert_adjacents node_c, [a ,b, d]
    assert_adjacents node_d, [b, c]

    assert [b, d] == Astar.find_path(node_a, graph, node_d) |> Enum.map(&(&1.entity))

    graph_with_points = GameMap.append_graph(graph, map, [start_point, end_point])
    node_start = Graph.get_node(graph_with_points, Entity.to_atom(start_point))
    node_end   = Graph.get_node(graph_with_points, Entity.to_atom(end_point))

    assert_adjacents node_start, [a, b]
    assert_adjacents node_end, [c, d]

    assert [a, c, end_point] == Astar.find_path(node_start, graph_with_points, node_end) |> Enum.map(&(&1.entity))
  end

  def assert_adjacents(%{ adjacents: adjacents }, expected_entities) do
    assert Enum.map(expected_entities, &(Entity.to_atom(&1))) == Map.keys(adjacents)
  end
end
