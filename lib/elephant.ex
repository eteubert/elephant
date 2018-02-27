defmodule Elephant do
  @moduledoc ~S"""
  Elephant: A STOMP client.

  Use `Elephant` as the primary API and `Elephant.Message` for working with received messages.

  ## Example

      {:ok, pid} = Elephant.start_link
      Elephant.connect(pid, {127,0,0,1}, 61613, "admin", "admin")

      callback = fn m -> IO.puts(inspect(m)) end

      Elephant.subscribe(pid, "foo.bar", callback)

      Elephant.disconnect(pid)

  For more control, use pattern matching in the callback:

      callback = fn
        %Elephant.Message{command: :message, headers: headers, body: body} ->
          Logger.info(["Received MESSAGE", "\nheaders: ", inspect(headers), "\nbody: ", inspect(body)])

        %Elephant.Message{command: :error, headers: headers, body: body} ->
          Logger.error(["Received ERROR", "\nheaders: ", inspect(headers), "\nbody: ", inspect(body)])

        %Elephant.Message{command: cmd, headers: headers, body: body} ->
          Logger.error([
            "Received unknown command: ", cmd, 
            "\nheaders: ",
            inspect(headers),
            "\nbody: ",
            inspect(body)
          ])
      end

  ## Starting in a supervision tree

      children = [
        worker(Elephant, [%{}, [name: Elephant]])
      ]
  """

  use GenServer

  require Logger
  alias Elephant.{Message, Receiver, Socket, Subscriber}

  def init(args) do
    {
      :ok,
      args
      |> Map.put_new(:socket, nil)
      |> Map.put_new(:receiver, nil)
      |> Map.put_new(:subscriber, nil)
    }
  end

  def start_link(state \\ %{}, opts \\ []) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  @doc """
  Connect to server.

  `host` must be `inet:socket_address() | inet:hostname()`, for example `{127,0,0,1}`.
  """
  def connect(pid, host, port, login, password) do
    GenServer.call(pid, {:connect, host, port, login, password})
  end

  @doc """
  Subscribe to a queue and register a callback for received messages.
  """
  def subscribe(pid, destination, callback) do
    GenServer.call(pid, {:subscribe, destination, callback})
  end

  @doc """
  Unsubscribe from a queue.
  """
  def unsubscribe(pid, destination) do
    GenServer.call(pid, {:unsubscribe, destination})
  end

  @doc """
  Receive messages from the TCP socket.

  Is called automatically when necessary. Should not be called manually.
  """
  def receive(pid, message) do
    GenServer.call(pid, {:receive, message})
  end

  @doc """
  Disconnect from server.
  """
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  def handle_call(
        {:receive, message = %Message{command: :message}},
        _from,
        state = %{subscriber: subscriber}
      ) do
    {:ok, "/queue/" <> destination} = Message.get_header(message, "destination")

    %{callback: callback} = Subscriber.get_subscription(subscriber, destination)

    callback.(message)

    {:reply, :ok, state}
  end

  def handle_call({:connect, host, port, login, password}, _from, state) do
    {:ok, socket} = Socket.connect(host, port)
    Socket.send(socket, connect_message(login, password))
    {:ok, response} = Socket.receive(socket)

    {:ok, subscriber} = Subscriber.start_link()
    {:ok, receiver} = Receiver.start_link(%{socket: socket, consumer: self()})
    Receiver.listen(receiver)

    case Message.parse(response) do
      {:ok, %Message{command: :connected}, _} ->
        {:reply, socket, %{state | socket: socket, subscriber: subscriber, receiver: receiver}}

      _ ->
        {:reply, {:error, response}}
    end
  end

  @doc """
  Disconnects from server.

  Returns `{:ok, :disconnected}` or `{:error, :disconnect_failed, message}`.
  """
  def handle_call(:disconnect, _from, %{
        socket: socket,
        subscriber: subscriber,
        receiver: receiver
      }) do
    receipt_id = Enum.random(1000..1_000_000)
    Socket.send(socket, disconnect_message(receipt_id))

    Receiver.stop(receiver)
    Subscriber.stop(subscriber)

    case Socket.receive(socket) do
      {:error, :closed} ->
        {:reply, {:ok, :disconnected}, %{}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{}}

      {:ok, response} ->
        Logger.debug(response)

        {:ok, response_message, _} = Message.parse(response)

        if response_message.command == :receipt &&
             Message.has_header(response_message, {"receipt-id", receipt_id}) do
          {:reply, {:ok, :disconnected}, %{}}
        else
          {:reply, {:error, :disconnect_failed, response_message}, %{}}
        end
    end
  end

  def handle_call(
        {:subscribe, destination, callback},
        _from,
        state = %{socket: socket, subscriber: subscriber}
      ) do
    {:ok, entry} = Subscriber.subscribe(subscriber, destination, callback)
    message = subscribe_message(destination, entry.id)
    Socket.send(socket, message)
    {:reply, {:ok, entry}, state}
  end

  def handle_call(
        {:unsubscribe, destination},
        _from,
        state = %{socket: socket, subscriber: subscriber}
      ) do
    {:ok, entry} = Subscriber.unsubscribe(subscriber, destination)
    message = unsubscribe_message(entry.id)
    Socket.send(socket, message)
    {:reply, :ok, state}
  end

  defp connect_message(login, password) do
    %Message{
      command: :connect,
      headers: [
        {"accept-version", "1.2"},
        {"host", "localhost"},
        {"login", login},
        {"password", password}
      ]
    }
  end

  defp disconnect_message(receipt_id) do
    %Message{
      command: :disconnect,
      headers: [
        {"receipt-id", receipt_id}
      ]
    }
  end

  defp subscribe_message(destination, id) do
    %Message{
      command: :subscribe,
      headers: [
        {"destination", destination},
        {"ack", "auto"},
        {"id", id}
      ]
    }
  end

  defp unsubscribe_message(id) do
    %Message{
      command: :unsubscribe,
      headers: [
        {"id", id}
      ]
    }
  end
end
