defmodule GameMap do
  require Logger
  defstruct my_id: nil, width: nil, height: nil, players: [], planets: []

  # The user's player
  def get_me(map) do
    get_player(map, map.my_id)
  end

  # player_id: The id of the desired player
  # The player associated with player_id
  def get_player(map, player_id) do
    map
      |> all_players
      |> Enum.find(&(&1.player_id == player_id))
  end

  # List of all players
  def all_players(map) do
    map.players
  end

  # The planet associated with planet_id
  def get_planet(map, planet_id) do
    Enum.find(map.planets, &(&1.id == planet_id))
  end

  # List of all planets
  def all_planets(map) do
    Map.values(map.planets)
  end

  def all_entities(map) do
    all_planets(map) ++ all_ships(map)
  end

  def all_ships(map) do
    Enum.map(all_players(map), &Player.all_ships/1)
      |> List.flatten
  end

  def update(map, tokens) do
    {tokens, players} = tokens |> Player.parse
    {[], planets}     = tokens |> Planet.parse(all_ships(map))
    with_entities(map, {players, planets})
  end

  def with_entities(map, { players, planets }) do
    Map.merge(map, %{players: players, planets: planets})
  end

  # entity: The source entity to find distances from
  #
  # Returns a map of distances with the values being lists of entities at that distance
  def nearby_entities_by_distance(%GameMap{} = map, entity), do: nearby_entities_by_distance(map |> all_entities |> all_entities_except(entity), entity)
  def nearby_entities_by_distance(entities, entity) do
    Enum.reduce(entities, %{}, fn(foreign_entity, acc) ->
      distance = Position.calculate_distance_between(entity, foreign_entity)
      acc = Map.put_new(acc, distance, [])
      Map.put(acc, distance, acc[distance] ++ [foreign_entity])
    end)
  end

  def all_entities_except(entities, entity) do
    Enum.reject(entities, fn(other) ->
      entity == other
    end)
  end
end
