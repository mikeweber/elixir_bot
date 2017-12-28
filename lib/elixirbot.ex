defmodule Elixirbot do
  require Logger

  def make_move(map, last_turn) do
    Logger.info("Making a move")
    player = GameMap.get_me(map)
    commands = flying_ships(Player.all_ships(player))
      |> Enum.reduce(%{}, fn(ship, acc) ->
        Logger.info("in reduce 1: #{inspect last_turn[ship |> Ship.to_atom]}")
        x = %{ map: map, ship: ship }
          |> continue_last_turn(last_turn[ship |> Ship.to_atom])
        Logger.info("About to attempt docking with #{inspect x}")
        x = x
          |> attempt_docking
        Logger.info("Adding command with #{inspect x}")
        x
          |> add_command(acc)
      end)

    Logger.info("Find centroid")
    centroid = player |> Player.all_ships |> List.first
    Logger.info("Prioritizing by planet")
    planets_with_distances(map, centroid)
      |> prioritized_planets
      |> Enum.reduce(commands, fn(planet, acc) ->
        Logger.info("in reduce for Planet #{planet.id}")
        player
          |> Player.all_ships
          |> flying_ships
          |> without_orders(Map.merge(last_turn, commands))
          |> Enum.reduce(acc, fn(ship, inner_acc) ->
            Logger.info("in inner reduce for Ship #{ship.id}")
            navigate_for_docking(%{ map: map, ship: ship }, planet)
              |> add_command(inner_acc)
          end)
      end)
  end

  def add_command(nil, acc),                           do: acc
  def add_command(%Ship.Command{ command: nil }, acc), do: acc
  def add_command(%Ship.Command{} = command, acc) do
    key = command.command.ship |> Ship.to_atom
    Logger.info("adding command for #{key}: #{inspect command}")
    Map.put_new(acc, key, command)
  end
  def add_command(x, y) do
    Logger.info("add_command catch all x: #{inspect x}")
    Logger.info("add_command catch all y: #{inspect y}")
  end

  def without_orders(ships, commands) do
    Logger.info("in without orders")
    Enum.reject(ships, fn(ship) ->
      Logger.info("in reject for #{Ship.to_atom(ship)}")
      Map.has_key?(commands, Ship.to_atom(ship))
    end)
  end

  def continue_last_turn(state, nil), do: state
  def continue_last_turn(state, %Ship.Command{ intent: %Ship.DockCommand{ planet: planet } }) do
    Logger.info("continuing last_turn: #{inspect planet}")
    Logger.info("continuing last_turn state: #{inspect Map.keys(state)}")
    if command = attempt_docking(planet, state) do
      command
    else
      navigate_for_docking(state, planet)
    end
  end
  def continue_last_turn(state, turn) do
    Logger.info("catch all state: #{inspect state}")
    Logger.info("catch all turn: #{inspect turn}")
    state
  end

  def attempt_docking(%Ship.Command{} = command), do: command
  def attempt_docking(%{ map: map, ship: ship } = state) do
    nearby_planets(map, ship) |> List.first |> attempt_docking(state)
  end
  def attempt_docking(x) do
    Logger.info("attempt_docking catch all #{inspect x}")
  end
  def attempt_docking(%Planet{} = planet, %{ map: _, ship: ship }) do
    Logger.info("attempt docking: #{inspect planet}")
    Logger.info("attempt docking not full?: #{inspect !Planet.is_full?(planet)}")
    if Ship.can_dock?(ship, planet) && !Planet.is_full?(planet) do
      Ship.dock(%{ ship: ship, planet: planet })
    end
  end
  def attempt_docking(x, y) do
    Logger.info("attempt_docking catch all x: #{inspect x}")
    Logger.info("attempt_docking catch all y: #{inspect y}")
  end

  def navigate_for_docking(%{ map: map, ship: ship }, planet, speed \\ 7) do
    Logger.info("navigate_for_docking")
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

  def make_move_for_ship(map, ship) do
    # For each planet in the game that doesn't have an owner (only non-destroyed planets are included)
    Enum.find_value(unowned_planets(GameMap.all_planets(map)), fn(planet) ->
      if command = Ship.try_to_dock(%{ ship: ship, planet: planet }) do
        # If we can dock, let's (try to) dock. If two ships try to dock at once, neither will be able to.
        command
      else
        # If we can't dock, we move towards the closest empty point near this planet (by using closest_point_to)
        # with constant speed. Don't worry about pathfinding for now, as the command will do it for you.
        # We run this navigate command each turn until we arrive to get the latest move.
        # Here we move at half our maximum speed to better control the ships
        # In order to execute faster we also choose to ignore ship collision calculations during navigation.
        # This will mean that you have a higher probability of crashing into ships, but it also means you will
        # make move decisions much quicker. As your skill progresses and your moves turn more optimal you may
        # wish to turn that option off.
        #
        # If a move is possible, return it so it can be added to the command_queue (if there are too many obstacles on the way
        # or we are trapped (or we reached our destination!), navigate_command will return null;
        # don't fret though, we can run the command again the next turn)
        Ship.navigate(
          ship,
          Position.closest_point_to(ship, planet),
          map,
          :math.floor(GameConstants.max_speed / 2.0),
          [ignore_ships: true]
        )
      end
    end)
  end

  def unowned_planets(planets) do
    Enum.reject(planets, &Planet.is_owned?/1)
  end

  def flying_ships(ships) do
    Enum.filter(ships, fn(ship) ->
      ship.docking_status == DockingStatus.undocked
    end)
  end
end
