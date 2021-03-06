# A ship in the game.
#
# id: The ship ID.
# x: The ship x-coordinate.
# y: The ship y-coordinate.
# radius: The ship radius.
# health: The ship's remaining health.
# docking_status: The docking status (UNDOCKED, DOCKED, DOCKING, UNDOCKING)
# docking_progres: How many turns the ship has been docking/undocking
# planet: The ID of the planet the ship is docked to, if applicable.
# owner: The player ID of the owner, if any. If nil, Entity is not owned.
defmodule Ship do
  require Position
  import Elixirbot.Util

  defstruct id: nil, owner: nil, x: nil, y: nil, radius: GameConstants.ship_radius, health: nil, docking_status: nil, docking_progress: nil, planet: nil

  defmodule ThrustCommand do
    defstruct ship: nil, magnitude: nil, angle: nil

    def string(%ThrustCommand{ ship: ship, magnitude: magnitude, angle: angle }) do
      "t #{ship.id} #{round(:math.floor(magnitude))} #{round(angle)}"
    end
  end

  defmodule DockCommand do
    defstruct ship: nil, planet: nil

    def string(%DockCommand{ ship: ship, planet: planet }) do
      "d #{ship.id} #{planet.id}"
    end
  end

  defmodule UndockCommand do
    defstruct ship: nil

    def string(%UndockCommand{ ship: ship }) do
      "u #{ship.id}"
    end
  end

  defmodule AttackCommand do
    defstruct ship: nil, target: nil
  end

  defmodule DefendPlanetCommand do
    defstruct ship: nil, target: nil
  end

  defmodule Command do
    defstruct command: nil, intent: nil

    def string(%ThrustCommand{} = command),   do: ThrustCommand.string(command)
    def string(%DockCommand{} = command),     do: DockCommand.string(command)
    def string(%UndockCommand{} = command),   do: UndockCommand.string(command)
    def string(%Command{ command: command }), do: Command.string(command)
    def string(_), do: nil
  end

  def has_orders?(nil), do: false
  def has_orders?(%Command{ command: nil }), do: false
  def has_orders?(%Command{}), do: true
  def has_orders?(%Ship{} = ship, %{} = command_map), do: has_orders?(ship |> to_atom, command_map)
  def has_orders?(ship_id, %{} = command_map), do: has_orders?(command_map[ship_id])

  def get(ships, ship_id), do: Enum.find(ships, &(ship_id == &1.id))

  def to_atom(ship), do: String.to_atom("ship#{ship.id}")

  # Determine whether a ship can dock to a planet
  #
  # planet: The planet wherein you wish to dock
  # Returns whether a ship can dock or not
  def can_dock?(%Ship{} = ship, %Planet{ owner: nil } = planet),                 do: dockable?(ship, planet)
  def can_dock?(%Ship{ owner: owner } = ship, %Planet{ owner: owner } = planet), do: dockable?(ship, planet)
  def can_dock?(_, _), do: false

  def dockable?(ship, planet), do: !Planet.is_full?(planet) && in_docking_range?(ship, planet)

  def in_docking_range?(ship, %Planet{} = planet) do
    in_range?(ship, planet, GameConstants.dock_radius + GameConstants.ship_radius)
  end
  def in_docking_range?(ship, %Ship{} = docked_ship), do: in_range?(ship, docked_ship, 1)

  def in_range?(ship, planet, range) do
    Position.calculate_distance_between(ship, planet) <= planet.radius + range
  end

  # Return a dock command if we can dock
  def try_to_dock(%{ship: ship, planet: planet} = params) do
    if can_dock?(ship, planet), do: dock(params)
  end

  def starburst(ship, centroid, speed \\ 4) do
    thrust(%{ ship: ship, magnitude: speed, angle: Position.calculate_deg_angle_between(centroid, ship)})
  end

  # Generate a command to accelerate this ship.

  # :param int magnitude: The speed through which to move the ship
  # :param int angle: The angle to move the ship in
  # :return: The command string to be passed to the Halite engine.
  def thrust(params) do
    %Command{ command: struct(ThrustCommand, params) }
  end

  # Generate a command to dock to a planet.

  # :param Planet planet: The planet object to dock to
  # :return: The command string to be passed to the Halite engine.
  def dock(params) do
    %Command{ command: struct(DockCommand, params) }
  end

  # Generate a command to undock from the current planet.

  # :return: The command trying to be passed to the Halite engine.
  def undock(params) do
    %Command{ command: struct(UndockCommand, params) }
  end

  def attack(params) do
    %Command{ command: struct(AttackCommand, params), intent: struct(AttackCommand, params) }
  end

  # Move a ship to a specific target position (Entity). It is recommended to place the position
  # itself here, else navigate will crash into the target. If avoid_obstacles is set to True (default)
  # will avoid obstacles on the way, with up to max_corrections corrections. Note that each correction accounts
  # for angular_step degrees difference, meaning that the algorithm will naively try max_correction degrees before giving
  # up (and returning nil). The navigation will only consist of up to one command; call this method again
  # in the next turn to continue navigating to the position.

  # target: The entity to which you will navigate
  # game_map: The map of the game, from which obstacles will be extracted
  # speed: The (max) speed to navigate. If the obstacle is nearer, will adjust accordingly.
  # avoid_obstacles: Whether to avoid the obstacles in the way (simple pathfinding).
  # max_corrections: The maximum number of degrees to deviate per turn while trying to pathfind. If exceeded returns nil.
  # angular_step: The degree difference to deviate if the original destination has obstacles
  # ignore_ships: Whether to ignore ships in calculations (this will make your movement faster, but more precarious)
  # ignore_planets: Whether to ignore planets in calculations (useful if you want to crash onto planets)
  #
  # Return the command trying to be passed to the Halite engine or nil if movement is not possible within max_corrections degrees.
  def plot_course(%Ship{} = ship, target, %GameMap{ planet_graph: planet_graph } = map) do
    graph_with_endpoints = GameMap.append_graph(planet_graph, map, [ship, target])
    origin      = Graph.get_node(graph_with_endpoints, Entity.to_atom(ship))
    destination = Graph.get_node(graph_with_endpoints, Entity.to_atom(target))

    filtered_graph =
      origin
      |> Astar.find_path(graph_with_endpoints, destination)
      |> Enum.reduce(%Graph{}, fn(%GraphNode{ children: children } = _planet_node, graph) ->
        children
        |> Enum.reduce(graph, fn({_, %GraphNode{} = child_node}, graph) ->
          graph |> Graph.add_node(child_node)
        end)
      end)
      |> GameMap.append_graph(map, [ship, target])

    filtered_graph
    |> Graph.get_node(Entity.to_atom(ship))
    |> Astar.find_path(filtered_graph, destination)
  end

  def plot_course_and_navigate(%Ship{} = ship, target, %GameMap{} = map, speed \\ 7) do
    %GraphNode{ entity: new_target } = plot_course(ship, target, map) |> List.first
    navigate(ship, new_target, map, speed, false, 0, 1.0, true, true)
  end

  def navigate(ship, target, map, speed, options \\ []) do
    # Default options
    defaults = [avoid_obstacles: true, max_corrections: 21, angular_step: 1.0, ignore_ships: false, ignore_planets: false]
    %{ avoid_obstacles: avoid_obstacles, max_corrections: max_corrections, angular_step: angular_step, ignore_ships: ignore_ships, ignore_planets: ignore_planets } = Keyword.merge(defaults, options) |> Enum.into(%{})

    navigate(ship, target, map, speed, avoid_obstacles, max_corrections, angular_step, ignore_ships, ignore_planets)
  end

  def navigate(   _,      _,   _,     _,               _,               0,            _,            _,              _), do: %Command{}
  def navigate(ship, target, map, speed, avoid_obstacles, max_corrections, angular_step, ignore_ships, ignore_planets) do
    distance = Position.calculate_distance_between(ship, target)
    angle    = Position.calculate_deg_angle_between(ship, target)

    ignore = []
    ignore = if(ignore_ships,   do: ignore ++ [:ships],   else: ignore)
    ignore = if(ignore_planets, do: ignore ++ [:planets], else: ignore)

    if avoid_obstacles && length(Position.obstacles_between(map, ship, target, ignore)) > 0 do
      delta_radians = (angle + angular_step) / 180.0 * :math.pi
      new_target_dx = :math.cos(delta_radians) * distance
      new_target_dy = :math.sin(delta_radians) * distance
      new_target    = %Position{ x: ship.x + new_target_dx, y: ship.y + new_target_dy }
      nav_options   = [
        avoid_obstacles: avoid_obstacles,
        max_corrections: max_corrections - 1,
        angular_step:    angular_step * -1.3,
        ignore_ships:    ignore_ships,
        ignore_planets:  ignore_planets
      ]
      navigate(ship, new_target, map, speed, nav_options)
    else
      safe_speed = Enum.min([distance, speed])
      thrust(%{ ship: ship, magnitude: safe_speed, angle: angle })
    end
  end

  def parse(player_id, tokens) do
    [count_of_ships|tokens] = tokens

    {ships, tokens} = parse(parse_int(count_of_ships), player_id, tokens)

    {ships, tokens}
  end

  def parse(0, _, tokens), do: {[], tokens}
  def parse(count_of_ships, player_id, tokens) do
    [id, x, y, hp, _, _, status, planet, progress, _|tokens] = tokens

    ship = %Ship{
      id:               parse_int(id),
      owner:            player_id,
      x:                parse_float(x),
      y:                parse_float(y),
      health:           parse_int(hp),
      docking_status:   parse_int(status),
      docking_progress: parse_int(progress),
      planet:           if((parse_int(status) == 1), do: parse_int(planet))
    }

    {ships, tokens} = parse(count_of_ships - 1, player_id, tokens)
    {ships++[ship], tokens}
  end
end
