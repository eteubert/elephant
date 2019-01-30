defmodule Elephant.Receiver do
  use GenServer

  require Logger
  alias Elephant.Message

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
        Logger.warn("[Elephant] Stopped listening because socket was closed.")
    end

    {:noreply, state}
  end

  def handle_response(consumer, response) do
    case Message.parse(response) do
      {:incomplete, message} ->
        Logger.debug(inspect(message))
        Elephant.receive(consumer, message)
        GenServer.cast(self(), :listen)

      # 1> I don't know if I need to :listen again here or what this is about
      # 2> I should just store incomplete messages in ETS or GenServer state
      # 3> Then when a new msg comes in, see if an incomplete is there an concat before parsing
      # 4> Then ensure this works recursively, if a message is split in 3+ parts

      {:ok, message, more} ->
        Logger.debug(inspect(message))
        Elephant.receive(consumer, message)
        handle_response(consumer, more)

      _ ->
        Logger.warn(
          "[Elephant] Unable to parse response: #{
            inspect(response, limit: :infinity, printable_limit: :infinity, pretty: true)
          }"
        )
    end
  end
end
