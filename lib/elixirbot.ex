defmodule Elixirbot do
  require Logger

  def make_move(map, last_turn) do
    player = GameMap.get_me(map)
    commands = flying_ships(Player.all_ships(player))
      |> Enum.reduce(%{}, fn(ship, acc) ->
        %{ map: map, ship: ship }
          |> continue_last_turn(last_turn[ship |> Ship.to_atom], Map.merge(last_turn, acc))
          |> attempt_docking
          |> add_command(acc)
      end)

    centroid = find_centroid(player |> Player.all_ships |> flying_ships, Player.all_planets(map, player))

    # Target the closest, biggest planets for docking
    planets = planets_with_distances(map, centroid)
      |> prioritized_planets
      |> dockable_planets(player)

    flying_ships = player
      |> Player.all_ships
      |> flying_ships

    commands = planets
      |> Enum.reduce(commands, fn(planet, acc) ->
        if Planet.can_be_targeted_for_docking?(planet, Map.merge(last_turn, acc)) do
          flying_ships
            |> without_orders(Map.merge(last_turn, acc))
            |> Enum.reduce(acc, fn(ship, inner_acc) ->
              Logger.info("Ship #{ship.id} might navigate towards Planet #{planet.id}")
              navigate_for_docking(%{ map: map, ship: ship }, planet, Map.merge(last_turn, inner_acc))
                |> add_command(inner_acc)
            end)
          else
            acc
          end
      end)

    # Starting with the ships furthest from the centroid, start attacking the closest enemies
    ships = player
      |> Player.all_ships
      |> flying_ships
      |> without_orders(Map.merge(last_turn, commands))

    ships = ships
      |> GameMap.nearby_entities_by_distance_sqrd(centroid)
      |> furthest_away
    Logger.info("Ships without orders (sorted): #{inspect ships}")
    ships
      |> Enum.reduce(commands, fn(ship, cmds) ->
        planets_with_distances(map, ship)
          |> prioritized_planets
          |> enemy_planets(player)
          |> List.first
          |> Planet.all_docked_ships
          |> Enum.reject(&is_nil/1)
          |> List.first
          |> navigate_for_attacking(%{ map: map, ship: ship })
          |> add_command(cmds)
      end)
  end

  def find_centroid([], planets), do: planets |> find_centroid
  def find_centroid(ships, _),    do: ships |> find_centroid
  def find_centroid(entities) do
    sums = entities
      |> Enum.reduce(%{ x: 0.0, y: 0.0 }, fn(pos, %{ x: x, y: y }) ->
        %{ x: x + pos.x, y: y + pos.y }
      end)
    %Position{ x: sums.x / (length(entities) / 1), y: sums.y / (length(entities) / 1)}
  end

  def add_command(nil, acc),                           do: acc
  def add_command(%Ship.Command{ command: nil }, acc), do: acc
  def add_command(%Ship.Command{ command: %{ ship: ship }} = command, acc) do
    Map.put_new(acc, (ship |> Ship.to_atom), command)
  end
  def add_command(_, acc), do: acc

  def without_orders(ships, commands) do
    Enum.reject(ships, &Ship.has_orders?(&1, commands))
  end

  def continue_last_turn(state, nil, _), do: state
  def continue_last_turn(state, %Ship.Command{ intent: nil }, _), do: state
  def continue_last_turn(state, %Ship.Command{ intent: %Ship.DockCommand{ planet: planet } }, orders) do
    attempt_docking(state, planet) || navigate_for_docking(state, planet, orders)
  end
  def continue_last_turn(%{ map: map } = state, %Ship.Command{ intent: %Ship.AttackCommand{ target: target } }, _) do
    if Ship.get(GameMap.all_ships(map), target.id) do
      navigate_for_attacking(target, state)
    else
      state
    end
  end

  # Fall through when a previous function may have already returned a command
  def attempt_docking(%Ship.Command{} = command), do: command
  # If the nearest planet is in range and has room, dock
  def attempt_docking(%{ map: map, ship: ship } = state) do
    planet = nearby_planets(map, ship) |> List.first
    attempt_docking(state, planet)
  end
  def attempt_docking(%{ ship: ship }, %Planet{} = planet) do
    Ship.try_to_dock(%{ ship: ship, planet: planet })
  end

  def navigate_for_docking(%{ map: map, ship: ship } = state, planet, orders, speed \\ 7) do
    if Planet.can_be_targeted_for_docking?(planet, ship, orders) do
      %{
        Ship.navigate(ship, Position.closest_point_to(ship, planet), map, speed)
        |
        intent: %Ship.DockCommand{ ship: ship, planet: planet }
      }
    else
      state
    end
  end

  def navigate_for_attacking(nil, state), do: state
  def navigate_for_attacking(target, %{ map: map, ship: ship }, speed \\ 7) do
    if in_attack_range?(ship, target) do
      Ship.attack(%{ ship: ship, target: target })
    else
      %{
        Ship.navigate(ship, target, map, speed)
        |
        intent: %Ship.AttackCommand{ ship: ship, target: target }
      }
    end
  end

  def in_attack_range?(ship, target) do
    Position.calculate_distance_between(ship, target) <= GameConstants.weapon_radius
  end

  def nearby_planets(map, origin) do
    planets_with_distances(map, origin)
      |> Enum.sort_by(fn({ dist, _ }) ->
        dist
      end)
      |> Keyword.values
      |> List.flatten
  end

  def prioritized_planets(planets) do
    planets
      |> Enum.sort_by(fn({ dist, planet }) ->
         dist / (planet.num_docking_spots / 1)
      end)
      |> Keyword.values
  end

  def furthest_away(entities) do
    entities
      |> Enum.sort_by(fn({ dist, _ }) ->
        -dist
      end)
      |> Keyword.values
  end

  def planets_with_distances(map, origin) do
    map
      |> GameMap.all_planets
      |> GameMap.nearby_entities_by_distance(origin)
  end

  def dockable_planets(planets, %Player{} = player) do
    planets
      |> Enum.filter(fn(planet) ->
        Planet.dockable?(player, planet)
      end)
  end

  def enemy_planets(planets, %Player{} = player) do
    planets
      |> Enum.filter(fn(planet) ->
        Planet.belongs_to_enemy?(player, planet)
      end)
  end

  def flying_ships(ships) do
    Enum.filter(ships, fn(ship) ->
      ship.docking_status == DockingStatus.undocked
    end)
  end
end
