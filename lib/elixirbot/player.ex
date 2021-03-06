defmodule Player do
  import Elixirbot.Util

  defstruct player_id: nil, ships: []

  def all_ships(nil), do: []
  def all_ships(player) do
    player.ships
  end

  def limited_ships(player) do
    player
    |> all_ships
    |> Enum.slice(0, 75)
  end

  def all_planets(%GameMap{} = map, %Player{} = player) do
    map
      |> GameMap.all_planets
      |> all_planets(player)
  end
  def all_planets(planets, %Player{} = player) do
    planets
      |> Enum.filter(fn(planet) ->
        planet.owner == player.player_id
      end)
  end

  def get_ship(player, ship_id) do
    Ship.get(all_ships(player), ship_id)
  end

  def parse(tokens) do
    [count_of_players|tokens] = tokens

    {players, tokens} = parse(parse_int(count_of_players), tokens)

    {tokens, players}
  end

  def parse(0, tokens), do: {[], tokens}
  def parse(count_of_players, tokens) do
    [player_id|tokens] = tokens
    player_id = parse_int(player_id)
    {ships, tokens} = Ship.parse(player_id, tokens)

    player = %Player{player_id: player_id, ships: ships}

    {players, tokens} = parse(count_of_players - 1, tokens)
    {players++[player], tokens}
  end
end
