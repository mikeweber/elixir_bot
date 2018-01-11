defmodule GraphNode do
  defstruct name: nil, entity: nil, adjacents: %{}, children: %{}

  def add_node(nodes, %GraphNode{ name: name } = new_node) do
    nodes |> Map.put(name, new_node)
  end

  def add_child(%GraphNode{ children: children } = parent_node, %GraphNode{} = child_node) do
    %{ parent_node | children: Map.put(children, child_node.name, child_node) }
  end

  def get_child(%GraphNode{ children: children }, name) do
    children |> Map.get(name)
  end

  def add_edge(%GraphNode{ adjacents: adjacents } = origin, %{ name: neighbor_name, entity: neighbor_entity }, weight) do
    %{ origin | adjacents: adjacents |> Map.put(neighbor_name, {weight, neighbor_entity}) }
  end

  def get_edge_weight(from, to) do
    from.adjacents[to.name]
  end
end

defmodule Graph do
  require Logger
  defstruct nodes: %{}

  def add_edge(%Graph{} = graph, %GraphNode{} = node_a, %GraphNode{} = node_b, magnitude) do
    node_a = node_a |> GraphNode.add_edge(node_b, magnitude)
    node_b = node_b |> GraphNode.add_edge(node_a, magnitude)

    { graph |> add_node(node_a) |> add_node(node_b), node_a, node_b}
  end

  def add_node(%Graph{ nodes: nodes }, %GraphNode{} = new_node) do
    %Graph{ nodes: nodes |> GraphNode.add_node(new_node) }
  end

  def find_or_create_node(%Graph{ nodes: nodes }, {name, entity}) do
    Map.get(nodes, name, %GraphNode{ entity: entity, name: name })
  end

  def get_node(%Graph{ nodes: nodes}, name) do
    Map.get(nodes, name)
  end
end

defimpl Inspect, for: Graph do
  def inspect(_, _) do
    "%Graph{}"
  end
end
