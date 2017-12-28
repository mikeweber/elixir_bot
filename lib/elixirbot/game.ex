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

  def update_map(map) do
    GameMap.update(map, input_tokens())
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
      |> Enum.reject(&is_nil(&1))
      |> Enum.map(fn(cmd) -> Ship.Command.string(cmd.command) end)
      |> Enum.join(" ")
      |> log_message
      |> write_to_output
  end

  def log_message(message) do
    Logger.debug("Sending: #{inspect message}")
    message
  end

  def run(map, last_turn \\ %{}, turn_num \\ 0) do
    Logger.info("---- Turn #{turn_num} ----")
    this_turn = map
      |> update_map
      |> Elixirbot.make_move(last_turn)

    Logger.info("this_turn: #{inspect this_turn}")
    this_turn
      |> Map.values
      |> send_command_queue

    run(map, this_turn, turn_num + 1)
  end
end
