defmodule GameMap do
  defstruct my_id: nil, turn: 0, width: nil, height: nil, players: [], planets: [], chart: %{}

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
    graph = planet_graph(map)
    %{ map | chart: graph }
  end

  def planet_graph(map) do
    build_graph(map, %Graph{}, all_planets(map))
  end

  def build_graph(map, graph, entities) do
    entities
    |> Enum.reduce({0, graph}, fn(entity, {index, graph})->
      entity_node = Graph.find_or_create_node(graph, { Position.to_atom(entity), entity })

      {
        index + 1,
        elem(entities |> Enum.split(index + 1), 1)
        |> Enum.reduce(graph, fn(other_entity, inner_graph) ->
          if (length(Position.obstacles_between(map, entity, other_entity, [:ships])) > 0) do
            # if another entity lies between entity and other_entity, don't add an edge to the graph
            inner_graph
          else
            # Calculate the minimum number of steps it would take to get to the target
            steps = Float.ciel(Position.calculate_distance_between(entity, other_entity) / 7.0)
            other_node = Graph.find_or_create_node(graph, { Position.to_atom(other_entity), other_entity })
            inner_graph |> Graph.add_edge(entity_node, other_node, steps) |> elem(0)
          end
        end)
      }
    end)
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
