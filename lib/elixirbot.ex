defmodule Elixirbot do
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

    planets_with_distances(map, centroid)
      |> dockable_planets(player)
      |> prioritized_planets
      |> Enum.reduce(commands, fn(planet, acc) ->
        player
          |> Player.all_ships
          |> flying_ships
          |> without_orders(Map.merge(last_turn, commands))
          |> Enum.reduce(acc, fn(ship, inner_acc) ->
            navigate_for_docking(%{ map: map, ship: ship }, planet)
              |> add_command(inner_acc)
          end)
      end)
  end

  def find_centroid([], planets), do: planets |> find_centroid
  def find_centroid(ships, _),    do: ships |> find_centroid
  def find_centroid(entities) do
    entities |> List.first
  end

  def add_command(nil, acc),                           do: acc
  def add_command(%Ship.Command{ command: nil }, acc), do: acc
  def add_command(%Ship.Command{} = command, acc) do
    key = command.command.ship |> Ship.to_atom
    Map.put_new(acc, key, command)
  end

  def without_orders(ships, commands) do
    Enum.reject(ships, fn(ship) ->
      Map.has_key?(commands, Ship.to_atom(ship))
    end)
  end

  def continue_last_turn(state, nil, _), do: state
  def continue_last_turn(state, %Ship.Command{ intent: nil }, _), do: state
  def continue_last_turn(state, %Ship.Command{ intent: %Ship.DockCommand{ planet: planet } }, orders) do
    target_for_docking(state, planet, orders) || navigate_for_docking(state, planet)
  end

  def target_for_docking(%Ship.Command{} = command), do: command
  def target_for_docking(%Planet{} = planet, %{ ship: ship } = state, orders) do
    if Planet.has_room?(planet, ship, orders), do: attempt_docking(planet, state)
  end

  # Fall through when a previous function may have already returned a command
  def attempt_docking(%Ship.Command{} = command), do: command
  # If the nearest planet is in range and has room, dock
  def attempt_docking(%{ map: map, ship: ship } = state) do
    nearby_planets(map, ship) |> List.first |> attempt_docking(state)
  end
  def attempt_docking(%Planet{} = planet, %{ ship: ship }) do
    Ship.try_to_dock(%{ ship: ship, planet: planet })
  end

  def navigate_for_docking(%{ map: map, ship: ship }, planet, speed \\ 7) do
    %{
      Ship.navigate(ship, Position.closest_point_to(ship, planet), map, speed)
      |
      intent: %Ship.DockCommand{ ship: ship, planet: planet }
    }
  end

  def nearby_planets(map, origin) do
    planets_with_distances(map, origin)
      |> Map.values
      |> List.flatten
  end

  def prioritized_planets(planets) do
    planets
      |> Enum.sort_by(fn({ dist, planets }) ->
         dist / (List.first(planets).num_docking_spots / 1)
      end)
      |> Keyword.values
      |> List.flatten
  end

  def planets_with_distances(map, origin) do
    map
      |> GameMap.all_planets
      |> GameMap.nearby_entities_by_distance(origin)
  end

  def dockable_planets(planets, %Player{} = player) do
    Enum.reject(planets, &Planet.dockable?(&1, player)/2)
  end

  def flying_ships(ships) do
    Enum.filter(ships, fn(ship) ->
      ship.docking_status == DockingStatus.undocked
    end)
  end
end
