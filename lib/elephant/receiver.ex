defmodule Elephant.Receiver do
  use GenServer

  require Logger
  alias Elephant.{Message, Socket}

  # Client

  def init(args) do
    {:ok, args}
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def subscribe(pid, destination) do
    GenServer.call(pid, {:subscribe, destination})
  end

  def listen(pid) do
    GenServer.cast(pid, :listen)
  end

  # Server

  def handle_call({:subscribe, destination}, _from, state = %{subscriptions: subscriptions}) do
    if Map.has_key?(subscriptions, destination) do
      {:reply, {:error, "You have already subscribed to this destination"}, state}
    else
      do_subscribe(destination, state)
    end
  end

  defp do_subscribe(destination, state = %{conn: conn, subscriptions: subscriptions}) do
    id = next_id(subscriptions)

    message = %Message{
      command: :subscribe,
      headers: [
        {"destination", destination},
        {"ack", "auto"},
        {"id", id}
      ]
    }

    Socket.send(conn, message)

    {:reply, :subscribed, %{state | subscriptions: Map.put(subscriptions, destination, id)}}
  end

  def next_id(subscriptions) do
    (subscriptions
     |> Map.values()
     |> Enum.max(fn -> 0 end)) + 1
  end

  def handle_cast(:listen, state = %{conn: conn, callback: callback}) do
    # TODO: unsubscribe

    case :gen_tcp.recv(conn, 0) do
      {:ok, response} ->
        Logger.debug(response)
        handle_response(response, callback)

      {:error, :closed} ->
        Logger.debug("Stopped listening because socket was closed.")
    end

    {:noreply, state}
  end

  def handle_response(response, callback) do
    case Message.parse(response) do
      {:ok, message, ""} ->
        Logger.debug(inspect(message))
        callback.(message)
        GenServer.cast(self(), :listen)

      {:ok, message, more} ->
        Logger.debug(inspect(message))
        callback.(message)
        handle_response(more, callback)
    end
  end
end
