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

    centroid = Position.find_centroid(player |> Player.all_ships |> flying_ships, Player.all_planets(map, player))

    # Target the closest, biggest planets for docking
    planets = planets_with_distances(map, centroid)
      |> prioritized_planets
      |> Keyword.values
      |> dockable_planets(player)

    flying_ships = player
      |> Player.all_ships
      |> flying_ships

    reinforcing_ships = flying_ships
      |> Enum.slice(0, reinforcement_strength(map, player, Map.merge(last_turn, commands)))

    # Reinforce
    Logger.info("Will reinforce with #{reinforcing_ships |> length} ships")
    commands = planets
      |> Enum.reduce(commands, fn(planet, acc) ->
        if Planet.can_be_targeted_for_docking?(planet, player, Map.merge(last_turn, acc)) do
          reinforcing_ships
            |> without_orders(Map.merge(last_turn, acc))
            |> Enum.reduce(acc, fn(ship, inner_acc) ->
              navigate_for_docking(%{ map: map, ship: ship }, planet, Map.merge(last_turn, inner_acc))
                |> add_command(inner_acc)
            end)
        else
          acc
        end
      end)

    # Starting with the ships furthest from the centroid, start attacking the closest enemies
    ships_without_orders = player
      |> Player.all_ships
      |> flying_ships
      |> without_orders(Map.merge(last_turn, commands))
      |> GameMap.nearby_entities_by_distance_sqrd(centroid)
      |> furthest_away
      |> Enum.slice(0, attack_strength(map, player, Map.merge(last_turn, commands)))

    Logger.info("Will attack with #{ships_without_orders |> length} ships")
    commands = ships_without_orders
      |> Enum.reduce(commands, fn(ship, cmds) ->
        enemy_planet = planets_with_distances(map, ship)
          |> prioritize_for_attack(map)
          |> Keyword.values
          |> enemy_planets(player)
          |> List.first
        if enemy_planet do
          enemy_planet
            |> Planet.all_docked_ships
            |> Enum.reject(&is_nil/1)
            |> List.first
            |> navigate_for_attacking(%{ map: map, ship: ship })
            |> add_command(cmds)
        else
          cmds
        end
      end)

    player
      |> Player.all_ships
      |> flying_ships
      |> without_orders(Map.merge(last_turn, commands))
      |> Enum.reduce(commands, fn(ship, cmds) ->
        my_planet = planets_with_distances(map, ship)
          |> prioritize_for_defense(Map.merge(last_turn, commands))
          |> Keyword.values
          |> my_planets(player)
          |> List.first
        if my_planet do
          my_planet
            |> navigate_for_defending(%{ map: map, ship: ship })
            |> add_command(cmds)
        else
          cmds
        end
      end)
  end

  def reinforcement_strength(map, player, orders) do
    num_ships       = map |> Player.all_planets(player) |> length
    reinforcers     = orders |> Enum.filter(fn({_, %Ship.Command{ intent: intent } })->
      is_docking?(intent)
    end) |> length
    reinforcers     = reinforcers + (map |> GameMap.docked_ships |> length)
    available_spots = map |> available_docking_spots
    Enum.max([Enum.min([Enum.max([num_ships / 3, 3]), available_spots]) - reinforcers, 0])
  end

  def attack_strength(map, player, orders) do
    num_ships = map |> Player.all_planets(player) |> length
    attackers = orders |> Enum.filter(fn({_, %Ship.Command{ intent: intent } })->
      is_attacking?(intent)
    end) |> length
    Enum.max([0, num_ships / 3 - attackers]) |> round
  end

  def is_docking?(%Ship.DockCommand{}), do: true
  def is_docking?(_), do: false
  def is_attacking?(%Ship.AttackCommand{}), do: true
  def is_attacking?(_), do: false

  def available_docking_spots(map) do
    GameMap.all_planets(map)
      |> Planet.dockable_planets(GameMap.get_me(map))
      |> Enum.reduce(0, fn(planet, sum)->
        sum + Planet.spots_left(planet)
      end)
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
  def continue_last_turn(%{ ship: ship } = state, %Ship.Command{ intent: %Ship.DockCommand{ planet: planet } }, orders) do
    if Planet.can_be_targeted_for_docking?(planet, ship, orders) do
      navigate_for_docking(state, planet, orders)
    else
      if Position.calculate_distance_between(planet, ship) - planet.radius <= 20 && length(planet.docked_ships) > 0 do
        navigate_for_attacking(planet.docked_ships |> List.first, state)
      else
        state
      end
    end
  end
  def continue_last_turn(%{ map: map } = state, %Ship.Command{ intent: %Ship.AttackCommand{ target: target } }, _) do
    if Ship.get(GameMap.all_ships(map), target.id) do
      navigate_for_attacking(target, state)
    else
      state
    end
  end
  def continue_last_turn(%{ ship: ship } = state, %Ship.Command{ intent: %Ship.DefendPlanetCommand{ target: target } }, _) do
    if Planet.belongs_to_me?(ship, target) do
      navigate_for_defending(target, state)
    else
      state
    end
  end

  def docking_spot(planet, ship, orders) do
    (planet.docked_ships |> List.first) || Enum.find(orders, fn({_, %Ship.Command{ intent: intent }}) ->
      if potential_ship = docking_ship(intent, planet) do
        unless ship.id == potential_ship.id do
          if potential_ship.docking_progress > 0, do: potential_ship
        end
      end
    end)
  end

  def docking_ship(%Ship.DockCommand{ ship: ship, planet: planet }, planet), do: ship
  def docking_ship(_, _), do: false

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
      if Ship.in_docking_range?(ship, planet) do
        attempt_docking(state, planet) || state
      else
        # Logger.info("Planet #{planet.id} is targeted by Ship #{ship.id}")
        %{
          Ship.navigate(ship, position_for_docking(ship, planet, orders), map, speed)
          |
          intent: %Ship.DockCommand{ ship: ship, planet: planet }
        }
      end
    else
      state
    end
  end

  def position_for_docking(%Ship{} = ship, %Planet{} = planet, nil), do: planet.docked_ships |> List.first || Position.closest_point_to(ship, planet, 3)
  def position_for_docking(%Ship{} = ship, %Planet{}, %Ship{} = docked_ship) do
    p = Position.closest_point_to(ship, docked_ship, 1)
    # Logger.info("Ship #{ship.id} is docking near ship #{docked_ship.id} at %{ x: #{p.x}, y: #{p.y} }")
    p
  end
  def position_for_docking(%Ship{} = ship, %Planet{} = planet, orders), do: position_for_docking(ship, planet, docking_spot(planet, ship, orders))

  def navigate_for_attacking(nil, state), do: state
  def navigate_for_attacking(target, %{ map: map, ship: ship }, speed \\ 7) do
    if in_attack_range?(ship, target) do
      Ship.attack(%{ ship: ship, target: target })
    else
      %{
        Ship.navigate(ship, Position.closest_point_to(ship, target, GameConstants.weapon_radius), map, speed)
        |
        intent: %Ship.AttackCommand{ ship: ship, target: target }
      }
    end
  end

  def navigate_for_defending(nil, state), do: state
  def navigate_for_defending(target, %{ map: map, ship: ship }, speed \\ 7) do
    %{
      # Navigate to the ships docked on the planet
      Ship.navigate(ship, defensive_position(ship, (target.docked_ships |> List.first) || target), map, speed)
      |
      intent: %Ship.DefendPlanetCommand{ ship: ship, target: target }
    }
  end

  def defensive_position(ship, %Planet{} = target) do
    Position.closest_point_to(ship, target, 3)
  end
  def defensive_position(ship, %Ship{} = docked_ship) do
    Position.closest_point_to(ship, docked_ship, 1)
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
  end

  def prioritize_for_attack(planets, map) do
    planets
      |> Enum.sort_by(fn({ dist, planet }) ->
        planet_attack_score(dist, planet, map)
      end)
  end

  def planet_dock_score(dist, planet, map) do
    normalized_distance(dist, map) / normalized_docking_score(planet, map)
  end

  def planet_attack_score(dist, planet, map) do
    num_docked_ships = planet.docked_ships |> length
    normalized_distance(dist, map) / normalized_docking_score(planet, map) * (1 - (num_docked_ships / planet.num_docking_spots))
  end

  def normalized_distance(dist, map) do
    dist / map.width
  end

  def normalized_docking_score(planet, map) do
    planet.num_docking_spots / Enum.max_by(GameMap.all_planets(map), &(&1.num_docking_spots)).num_docking_spots
  end

  def prioritize_for_defense(planets, orders) do
    planets
      |> Enum.reject(fn({_, planet}) ->
        planet.num_docking_spots * 1.5 <= (Planet.ships_defending(planet, orders) |> length)
      end)
      |> Enum.sort_by(fn({ dist, planet }) ->
        dist / planet.num_docking_spots
      end)
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

  def my_planets(planets, %Player{} = player) do
    planets |> Enum.reject(&Planet.belongs_to_enemy?(player, &1))
  end

  def enemy_planets(planets, %Player{} = player) do
    planets |> Enum.filter(&Planet.belongs_to_enemy?(player, &1))
  end

  def flying_ships(ships) do
    Enum.filter(ships, fn(ship) ->
      ship.docking_status == DockingStatus.undocked
    end)
  end
end
