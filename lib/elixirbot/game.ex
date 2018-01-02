defmodule Elixirbot.Game do
  require Logger
  require Map
  require Planet
  require Player
  require Ship
  require GameMap
  import Elixirbot.Util

  def connect(name) do
    player_id = read_from_input()
    set_up_logging(name, player_id)
    [width, height] = read_ints_from_input()
    Logger.info "game size: #{width} x #{height}"
    Logger.info "initializing bot #{inspect(name)}"
    write_to_output(name)
    %GameMap{my_id: parse_int(player_id), width: width, height: height}
      |> update_map
  end

  def update_map(map, turn \\ 0) do
    GameMap.update(map, turn, input_tokens())
  end

  defp input_tokens() do
    read_from_input() |> String.split(" ")
  end

  defp read_from_input() do
    IO.gets("") |> String.trim
  end

  defp set_up_logging(name, player_id) do
    Logger.add_backend {LoggerFileBackend, :debug}
    Logger.configure_backend {LoggerFileBackend, :debug}, path: "#{player_id}_#{name}.log"
    Logger.info "Starting new game for #{name}:#{player_id}"
  end

  def read_ints_from_input do
    read_from_input()
      |> String.split(" ")
      |> Enum.map(&parse_int/1)
  end

  defp write_to_output(message) do
    String.trim(message)
      |> IO.puts
  end

  def send_command_queue(commands) do
    commands
      |> log_commands
      |> Map.values
      |> Enum.filter(&Ship.has_orders?(&1))
      |> Enum.map(&Ship.Command.string(&1))
      |> Enum.join(" ")
      |> log_message
      |> write_to_output
    commands
  end

  def log_commands(commands) do
    Enum.each(commands, fn({ship_atom, cmd}) ->
      Logger.debug("#{ship_atom}: #{inspect cmd}")
    end)
    commands
  end

  def log_message(message) do
    Logger.debug("Sending: #{inspect message}")
    message
  end

  # First turn
  def run(map) do
    Logger.info("---- Turn 0 ----")
    ships = map |> update_map |> GameMap.get_me |> Player.all_ships
    centroid = Position.find_centroid(ships)
    ships
      |> Enum.reduce(%{}, fn(ship, cmds) ->
        Map.put(cmds, Ship.to_atom(ship), Ship.starburst(ship, centroid))
      end)
      |> send_command_queue

    run(map, %{}, 1)
  end
  def run(map, last_turn \\ %{}, turn_num) do
    Logger.info("---- Turn #{turn_num} ----")
    this_turn = determine_moves(map, turn_num, last_turn)
      |> send_command_queue

    run(map, this_turn, turn_num + 1)
  end

  def determine_moves(map, turn_num, last_turn) do
    try do
      map
        |> update_map(turn_num)
        |> Elixirbot.make_move(last_turn)
    rescue
      e ->
        stack = System.stacktrace
        Logger.error("#{inspect(Exception.message(e))}\n#{Exception.format_stacktrace(stack)}")
        raise e
    end
  end
end
