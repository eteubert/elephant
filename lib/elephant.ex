defmodule Elephant do
  @moduledoc ~S"""
  Elephant: A STOMP client.

  ## Example

      {:ok, pid} = Elephant.start_link
      Elephant.connect(pid, {127,0,0,1}, 61613, "admin", "admin")

      callback = fn m -> IO.puts(inspect(m)) end

      Elephant.subscribe(pid, "foo.bar", callback)
      Elephant.subscribe(pid, "foo2.bar", callback)

      Elephant.unsubscribe(pid, "foo2.bar")

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

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state)
  end

  @doc """
  Connect to server.

  Returns `{:ok, conn}` or `{:error, message}`.
  """
  def connect(pid, host, port, login, password) do
    GenServer.call(pid, {:connect, host, port, login, password})
  end

  def subscribe(pid, destination, callback) do
    GenServer.call(pid, {:subscribe, destination, callback})
  end

  def unsubscribe(pid, destination) do
    GenServer.call(pid, {:unsubscribe, destination})
  end

  def receive(pid, message) do
    GenServer.call(pid, {:receive, message})
  end

  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  def handle_call({:receive, message}, _from, state) do
    Logger.warn(inspect(message))

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

  @doc """
  Subscribe to a topic or queue.

  Steps to fix multiple subscriptions:
  - start Receiver only _once_ globally
  - listen only _once_ globally
  - attach callbacks to subscriptions/destinations, not the Receiver
  - check rest of code: except connect, it's send-and-forget, 
    don't wait for server response because we already have a listener running
  """
  # def subscribe(receiver, destination, callback) do
  #   Receiver.subscribe(receiver, destination, callback)
  # end
end
