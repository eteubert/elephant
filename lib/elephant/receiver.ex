defmodule Elephant.Receiver do
  use GenServer

  require Logger
  alias Elephant.{Message}

  # Client

  def init(args) do
    {:ok, args}
  end

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state)
  end

  def listen(pid) do
    GenServer.cast(pid, :listen)
  end

  def stop(server) do
    GenServer.stop(server)
  end

  # Server

  def handle_cast(:listen, state = %{socket: socket, consumer: consumer}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, response} ->
        # - todo fetch matching subscription based on header
        # - then extract callback from the entry
        Logger.debug(response)
        handle_response(consumer, response)

      {:error, :closed} ->
        Logger.debug("[Elephant] Stopped listening because socket was closed.")
    end

    {:noreply, state}
  end

  def handle_response(consumer, response) do
    case Message.parse(response) do
      {:ok, message, ""} ->
        Logger.debug(inspect(message))
        Elephant.receive(consumer, message)
        GenServer.cast(self(), :listen)

      {:ok, message, more} ->
        Logger.debug(inspect(message))
        Elephant.receive(consumer, message)
        handle_response(consumer, more)

      {:error, _} ->
        Logger.warn(
          "[Elephant] Unable to parse response: #{
            inspect(response, limit: :infinity, printable_limit: :infinity, pretty: true)
          }"
        )
    end
  end
end
