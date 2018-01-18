# https://www.redblobgames.com/pathfinding/a-star/introduction.html
defmodule Astar do
  require Logger

  def find_path(origin, graph, target) do
    traverse_graph({[{ 0, origin.name }], %{ origin.name => {0,nil} }}, graph, target)
    |> elem(1)
    |> rebuild_path(origin, target)
  end

  def inspector(graph) do
    IO.inspect(graph)
    graph
  end

  # What to do when one traversal is complete, but there are others to check?!
  def traverse_graph({[], came_from}, _, _), do: {[], came_from}
  def traverse_graph({frontier, came_from}, graph, target) do
    {current_node_name, frontier} = PriorityQueue.get(frontier)
    current_node = Graph.get_node(graph, current_node_name)

    deep_traverse({frontier, came_from}, graph, target, current_node)
  end

  def deep_traverse(state, _, target, target), do: state
  def deep_traverse({[], came_frome} = state, _, _, _), do: state
  def deep_traverse(state, graph, %{ entity: target_entity } = target, %GraphNode{ adjacents: adjacents, name: current_name } = current) do
    adjacents
    |> Enum.reduce(state, fn({next_name, {next_weight, next_entity}}, {frontier, came_from})->
      new_cost = (came_from[current_name] |> elem(0)) + next_weight
      prev_node = came_from[next_name]

      if prev_node && elem(prev_node, 0) <= new_cost do
        state
      else
        IO.inspect("Adding #{next_name} to frontier")
        {
          frontier  |> PriorityQueue.add({new_cost + heuristic(target_entity, next_entity), next_name}),
          came_from |> Map.put(next_name, {new_cost, current})
        }
      end
    end)
    |> inspector
    |> traverse_graph(graph, target)
  end

  def heuristic(%{ x: x1, y: y1 }, %{ x: x2, y: y2 }) do
    (:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2)) |> :math.sqrt
  end
  def heuristic(_, _), do: 0

  def rebuild_path(        _,      _,    nil), do: []
  def rebuild_path(        _, %{ name: origin }, %{ name: origin }), do: []
  def rebuild_path(came_from, origin, current) do
    IO.inspect("came from current: #{inspect came_from[current.name]}")
    if came_from[current.name] do
      rebuild_path(came_from, origin, (came_from[current.name]) |> elem(1)) ++ [current]
    else
      [current]
    end
  end
end

defmodule PriorityQueue do
  def add(queue, { weight, _ } = weighted_node) do
    loc = queue |> Enum.find_index(fn({ i_weight, _ }) ->
      i_weight < weight
    end)

    queue |> List.insert_at((loc || 0), weighted_node)
  end

  def get(queue) do
    { queue |> List.last |> elem(1), queue |> List.delete_at(-1) }
  end
end
