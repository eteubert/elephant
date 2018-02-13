defmodule Elephant.Receiver do
  use GenServer

  require Logger
  alias Elephant.Message

  # Client

  def init(args) do
    {:ok, args}
  end

  def start_link(conn) do
    GenServer.start_link(__MODULE__, conn)
  end

  def subscribe(pid, destination) do
    GenServer.call(pid, {:subscribe, destination})
  end

  def listen(pid) do
    GenServer.cast(pid, :listen)
  end

  # Server

  def handle_call({:subscribe, destination}, _from, conn) do
    message =
      %Message{
        command: :subscribe,
        headers: [
          {"destination", destination},
          {"ack", "auto"},
          {"id", "42"}
        ]
      }
      |> Message.format()

    Logger.debug(message)

    :gen_tcp.send(conn, message)

    {:reply, :subscribed, conn}
  end

  def handle_cast(:listen, conn) do
    # TODO: unsubscribe
    # TODO: register message handler

    Logger.debug("handle_info :listen")

    {:ok, response} = :gen_tcp.recv(conn, 0)
    Logger.debug(response)

    response_message =
      response
      |> :erlang.iolist_to_binary()
      |> Message.parse()

    Logger.debug(inspect(response_message))

    GenServer.cast(self(), :listen)

    {:noreply, conn}
  end
end
