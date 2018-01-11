defmodule GameMap do
  defstruct my_id: nil, turn: 0, width: nil, height: nil, players: [], planets: [], planet_graph: %{}, nav_points: %{}

  # The user's player
  def get_me(map), do: get_player(map, map.my_id)

  # player_id: The id of the desired player
  # The player associated with player_id
  def get_player(map, player_id) do
    map
      |> all_players
      |> Enum.find(&(&1.player_id == player_id))
  end

  # List of all players
  def all_players(map), do: map.players

  # The planet associated with planet_id
  def get_planet(map, planet_id), do: Enum.find(map.planets, &(&1.id == planet_id))

  # List of all planets
  def all_planets(map), do: Map.values(map.planets)

  def all_entities(map), do: all_planets(map) ++ all_ships(map)

  def all_ships(%GameMap{} = map), do: all_players(map) |> all_ships
  def all_ships(players) do
    players
      |> Enum.map(&Player.all_ships(&1))
      |> List.flatten
  end

  def docked_ships(map) do
    map
      |> all_planets
      |> Enum.reduce([], fn(planet, ships)->
        ships ++ planet.docked_ships
      end)
  end

  def update(map, turn, tokens) do
    {tokens, players} = tokens |> Player.parse
    {[], planets}     = tokens |> Planet.parse(players |> all_ships)
    with_entities(map, turn, {players, planets})
  end

  def with_entities(map, turn, { players, planets }) do
    Map.merge(map, %{ turn: turn, players: players, planets: planets})
  end

  def build_planet_graph(map) do
    planet_graph = build_nav_points(map, planet_graph(map))
    %{ map | planet_graph: planet_graph }
  end

  def build_nav_points(map, planetary_graph) do
    tau = 2 * :math.pi

    map
    |> all_planets
    |> Enum.reduce(planetary_graph, fn(%{ x: x, y: y } = planet, graph) ->

      # Place nav points, equally spaced and about 1 unit apart, in a circle 2 units above the surface of the planet
      radius = planet.radius + 2
      num_points = tau * radius |> round
      delta = tau / num_points

      graph = Enum.reduce(0..(num_points - 1), graph, fn(i, graph) ->
        point1 = %Position{ x: x + :math.cos(i * delta) * radius, y: y + :math.sin(i * delta) * radius }
        Enum.reduce((i + 1)..num_points, graph, fn(j, graph) ->
          point2 = %Position{ x: x + :math.cos(j * delta) * radius, y: y + :math.sin(j * delta) * radius }

          if Position.no_obstacles?(map, point1, point2, [:ships]) do
            planet_node = Graph.get_node(graph, Entity.to_atom(planet))
            {planet_node, node1} = find_or_create_child_node(planet_node, point1)
            {planet_node, node2} = find_or_create_child_node(planet_node, point2)

            # in theory, all of the points should be the same i - j distance apart
            graph
            |> Graph.add_node(planet_node)
            |> Graph.add_edge(node1, node2, clamp_distance(j - i, num_points) / 7)
            |> elem(0)
          else
            graph
          end
        end)
      end)

      graph.nodes
      |> Enum.reduce(graph, fn({_, %GraphNode{ adjacents: adjacents, children: planet_children, entity: planet }}, graph) ->
        # Now connect the point between the adjacent planets
        map
        |> all_planets
        |> Enum.filter(fn(potential_neighbor) ->
          Map.has_key?(adjacents, Entity.to_atom(potential_neighbor))
        end)
        |> Enum.map(fn(planet) ->
          Graph.get_node(graph, Entity.to_atom(planet))
        end)
        |> Enum.reduce(graph, fn(%GraphNode{ children: neighbor_children} = _neighbor_node, graph) ->
          planet_children
          |> reduce_planet_nodes(planet, neighbor_children, graph, map)
        end)
      end)
    end)
  end

  def reduce_planet_nodes(planet_points, planet, neighbor_points, graph, map) do
    planet_points
    |> Enum.reduce(graph, fn({_, %GraphNode{ entity: planet_point }}, graph) ->
      neighbor_points |> reduce_neighbor_nodes(planet_point, planet, graph, map)
    end)
  end

  def reduce_neighbor_nodes(neighbor_points, planet_point, planet, graph, map) do
    neighbor_points
    |> Enum.reduce(graph, fn({_, %GraphNode{ entity: neighbor_point } = neighbor_node}, graph) ->
      if Position.no_obstacles?(map, planet_point, neighbor_point, [:ships]) do
        {planet_node, node1} =
          graph
          |> Graph.get_node(Entity.to_atom(planet))
          |> find_or_create_child_node(planet_point)

        dist =
          (Position.calculate_distance_between(planet_point, neighbor_point) / 7)
          |> Float.ceil

        graph
        |> Graph.add_node(
          planet_node
          |> GraphNode.add_child(
            node1
            |> GraphNode.add_edge(neighbor_node, dist)
          )
        )
      else
        graph
      end
    end)
  end

  def find_or_create_child_node(parent_node, child) do
    if existing_node = GraphNode.get_child(parent_node, Entity.to_atom(child)) do
      {parent_node, existing_node}
    else
      new_node = %GraphNode{ name: Entity.to_atom(child), entity: child }
      {GraphNode.add_child(parent_node, new_node), new_node}
    end
  end

  # if a circle has 25 points, the distance between point 1 and point 25 is only 1
  def clamp_distance(dist, num_points) do
    :math.fmod(dist + num_points / 4, num_points / 2) - num_points / 4
  end

  def planet_graph(map) do
    build_graph(map, %Graph{}, all_planets(map))
  end

  def build_graph(map, graph, entities) do
    entities
    |> Enum.reduce({0, graph}, fn(entity, {index, graph})->
      {
        index + 1,
        entities |> Enum.split(index + 1) |> elem(1)
        |> Enum.reduce(graph, fn(other_entity, inner_graph) ->
          if Position.no_obstacles?(map, entity, other_entity, [:ships]) do
            # Calculate the minimum number of steps it would take to get to the target
            steps = Float.ceil(Position.calculate_distance_between(entity, other_entity) / 7.0)

            source_node = Graph.find_or_create_node(inner_graph, { Entity.to_atom(entity), entity })
            other_node  = Graph.find_or_create_node(inner_graph, { Entity.to_atom(other_entity), other_entity })
            inner_graph |> Graph.add_edge(source_node, other_node, steps) |> elem(0)
          else
            # if another entity lies between entity and other_entity, don't add an edge to the graph
            inner_graph
          end
        end)
      }
    end)
    |> elem(1)
  end

  def append_graph(graph, _, []), do: graph
  def append_graph(%Graph{ nodes: nodes } = graph, map, [new_entity | other_entities]) do
    Enum.reduce(nodes |> Map.values, graph, fn(%GraphNode{ entity: other_entity } = other_node, graph) ->
      if (length(Position.obstacles_between(map, new_entity, other_entity, [:ships])) > 0) do
        graph
      else
        new_node = Graph.find_or_create_node(graph, { Entity.to_atom(new_entity), new_entity })

        # Calculate the minimum number of steps it would take to get to the target
        steps = Float.ceil(Position.calculate_distance_between(new_entity, other_entity) / 7.0)
        Graph.add_edge(graph, new_node, other_node, steps) |> elem(0)
      end
    end)
    |> append_graph(map, other_entities)
  end

  # entity: The source entity to find distances from
  #
  # Returns a map of distances with the values being lists of entities at that distance
  def nearby_entities_by_distance(%GameMap{} = map, entity), do: nearby_entities_by_distance(map |> all_entities |> all_entities_except(entity), entity)
  def nearby_entities_by_distance(entities, entity) do
    Enum.reduce(entities, [], fn(foreign_entity, acc) ->
      distance = Position.calculate_distance_between(entity, foreign_entity)
      acc ++ [{ distance, foreign_entity }]
    end)
  end

  def nearby_entities_by_distance_sqrd(%GameMap{} = map, entity), do: nearby_entities_by_distance_sqrd(map |> all_entities |> all_entities_except(entity), entity)
  def nearby_entities_by_distance_sqrd(entities, entity) do
    Enum.reduce(entities, [], fn(foreign_entity, acc) ->
      distance = Position.calculate_sqrd_distance_between(entity, foreign_entity)
      acc ++ [{ distance, foreign_entity }]
    end)
  end

  def all_entities_except(entities, entity) do
    Enum.reject(entities, fn(other) ->
      entity == other
    end)
  end
end

