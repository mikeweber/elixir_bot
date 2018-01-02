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

    commands = planets
      |> Enum.reduce(commands, fn(planet, acc) ->
        if Planet.can_be_targeted_for_docking?(planet, player, Map.merge(last_turn, acc)) do
          flying_ships
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

    commands = ships_without_orders
      |> Enum.slice(0, attack_strength(ships_without_orders) |> round)
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

  def attack_strength(flying_ships) do
    length(flying_ships) * 2.0 / 3.0
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
      attempt_docking(state, planet) || navigate_for_docking(state, planet, orders)
    else
      state
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
        Ship.navigate(ship, Position.closest_point_to(ship, target, GameConstants.weapon_radius), map, speed)
        |
        intent: %Ship.AttackCommand{ ship: ship, target: target }
      }
    end
  end

  def navigate_for_defending(nil, state), do: state
  def navigate_for_defending(target, %{ map: map, ship: ship } = state, speed \\ 7) do
    %{
      if Ship.in_range?(ship, target, 7) do
        Planet.ships_in_attacking_range(target, map) |> defend_planet(state, target)
      else
        # Navigate to the planet
        Ship.navigate(ship, Position.closest_point_to(ship, target, GameConstants.dock_radius), map, speed)
      end
      |
      intent: %Ship.DefendPlanetCommand{ ship: ship, target: target }
    }
  end

  def defend_planet([], %{ ship: ship, map: map }, planet) do
    # "Orbit" the planet
    ship_angle = (Position.calculate_angle_between(planet, ship) |> Position.to_degrees)
    angle = (ship_angle + 9) |> Elixirbot.Util.angle_deg_clipped
    pos   = Position.in_orbit(planet, GameConstants.weapon_radius, angle)
    dist  = [Position.calculate_distance_between(ship, pos), 7] |> Enum.min
    Ship.navigate(ship, pos, map, :math.floor(dist))
  end
  def defend_planet(enemies, state, _) do
    # Attack the nearest ship
    navigate_for_attacking(enemies |> List.first, state)
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
