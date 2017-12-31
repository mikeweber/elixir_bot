# A planet on the game map.
#
# id: The planet ID.
# x: The planet x-coordinate.
# y: The planet y-coordinate.
# radius: The planet radius.
# num_docking_spots: The max number of ships that can be docked.
# health: The planet's health.
# owner: The player ID of the owner, if any. If nil, Entity is not owned.
defmodule Planet do
  import Elixirbot.Util

  defstruct id: nil, owner: nil, x: nil, y: nil, radius: nil, health: nil, num_docking_spots: nil, docked_ships: []

  def get_docked_ship(planet, id) do
    Enum.find(all_docked_ships(planet), fn(ship) ->
      ship.id == id
    end)
  end

  def all_docked_ships(planet) do
    planet.docked_ships
  end

  def is_owned?(planet) do
    planet.owner != nil
  end

  def can_be_targeted_for_docking?(planet, %Ship{} = ship, orders) do
    dockable?(ship, planet) && (planet |> spots_left) > (ships_targeting_planet_for_docking(orders, planet, ship) |> length)
  end
  def can_be_targeted_for_docking?(planet, %Player{} = player, orders) do
    dockable?(player, planet) && (planet |> spots_left) > (ships_targeting_planet_for_docking(orders, planet) |> length)
  end

  def spots_left(planet), do: planet.num_docking_spots - (planet |> all_docked_ships |> length)

  def dockable?(_, %Planet{ owner: nil}), do: true
  def dockable?(%Ship{ owner: owner }, %Planet{ owner: owner} = planet),                 do: !is_full?(planet)
  def dockable?(%Player{ player_id: player_id }, %Planet{ owner: player_id  } = planet), do: !is_full?(planet)
  def dockable?(_, _), do: false

  def ships_targeting_planet_for_docking(orders, planet, nil), do: ships_targeting_planet_for_docking(orders, planet)
  def ships_targeting_planet_for_docking(orders, planet, ship) do
    orders
      |> Enum.reject(fn({ ship_atom, _ }) ->
        ship_atom == (ship |> Ship.to_atom)
      end)
      |> ships_targeting_planet_for_docking(planet)
  end
  def ships_targeting_planet_for_docking(orders, planet) do
    orders
      |> Enum.filter(fn({ _, command }) ->
        command_targeting_planet?(command, planet)
      end)
  end

  def command_targeting_planet?(%Ship.Command{ command: %Ship.DockCommand{ planet: planet }}, planet), do: true
  def command_targeting_planet?(%Ship.Command{ intent: %Ship.DockCommand{ planet: planet }}, planet), do: true
  def command_targeting_planet?(_, _), do: false

  def belongs_to_enemy?(%Player{ player_id: player_id }, %Planet{ owner: player_id }), do: false
  def belongs_to_enemy?(%Ship{ owner: player_id }, %Planet{ owner: player_id }), do: false
  def belongs_to_enemy?(_, _), do: true

  def is_full?(planet) do
    length(all_docked_ships(planet)) >= planet.num_docking_spots
  end

  def parse(tokens, ships) do
    [count_of_planets|tokens] = tokens

    {planets, tokens} = parse(parse_int(count_of_planets), tokens, ships)

    {tokens, planets}
  end

  def parse(0, tokens, _), do: {%{}, tokens}
  def parse(count_of_planets, tokens, ships) do
    [id, x, y, hp, r, docking_spots, _, _, owned, owner, ship_count|tokens] = tokens

    # Fetch the ship ids from the tokens array
    {docked_ship_ids, tokens} = parse_docked_ship_ids(parse_int(ship_count), tokens)

    planet = %Planet{
      id:                parse_int(id),
      x:                 parse_float(x),
      y:                 parse_float(y),
      health:            parse_int(hp),
      radius:            parse_float(r),
      num_docking_spots: parse_int(docking_spots),
      owner:             if(parse_int(owned) == 0, do: nil, else: parse_int(owner)),
      docked_ships:      Enum.map(docked_ship_ids, fn(ship_id) ->
        Ship.get(ships, ship_id)
      end)
    }

    {planets, tokens} = parse(count_of_planets - 1, tokens, ships)
    {Map.merge(%{id => planet}, planets), tokens}
  end

  defp parse_docked_ship_ids(0, tokens), do: {[], tokens}
  defp parse_docked_ship_ids(ship_count, tokens) do
    [ship_id|tokens] = tokens
    {ship_ids, tokens} = parse_docked_ship_ids(ship_count - 1, tokens)
    {ship_ids++[parse_int(ship_id)], tokens}
  end
end
