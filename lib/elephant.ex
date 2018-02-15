defmodule Elephant do
  @moduledoc ~S"""
  Elephant: A STOMP client.

  ## Example

      {:ok, conn} = Elephant.connect({127,0,0,1}, 61613, "admin", "admin")

      callback = fn m -> IO.puts(inspect(m)) end

      Elephant.subscribe(conn, "foo.bar", callback)

      # when you are finished, disconnect
      Elephant.disconnect(conn)

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

  require Logger
  alias Elephant.{Message, Receiver, Socket}

  @doc """
  Connect to server.

  Returns `{:ok, conn}` or `{:error, message}`.
  """
  def connect(host, port, login, password) do
    {:ok, conn} = Socket.connect(host, port)
    Socket.send(conn, connect_message(login, password))
    {:ok, response} = Socket.receive(conn)

    case Message.parse(response) do
      {:ok, %Message{command: :connected}, _} -> {:ok, conn}
      _ -> {:error, response}
    end
  end

  @doc """
  Disconnects from server.

  Returns `{:ok, :disconnected}` or `{:error, :disconnect_failed, message}`.
  """
  def disconnect(conn) do
    receipt_id = Enum.random(1000..1_000_000)
    Socket.send(conn, disconnect_message(receipt_id))

    case Socket.receive(conn) do
      {:error, :closed} ->
        {:ok, :disconnected}

      {:error, reason} ->
        {:error, reason}

      {:ok, response} ->
        Logger.debug(response)

        {:ok, response_message, _} = Message.parse(response)

        if response_message.command == :receipt &&
             Message.has_header(response_message, {"receipt-id", receipt_id}) do
          {:ok, :disconnected}
        else
          {:error, :disconnect_failed, response_message}
        end
    end
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

  @doc """
  Subscribe to a topic or queue.

  Steps to fix multiple subscriptions:
  - start Receiver only _once_ globally
  - listen only _once_ globally
  - attach callbacks to subscriptions/destinations, not the Receiver
  - check rest of code: except connect, it's send-and-forget, 
    don't wait for server response because we already have a listener running
  """
  def subscribe(conn, destination, callback) do
    {:ok, pid} =
      Receiver.start_link(%{
        conn: conn,
        callback: callback,
        subscriptions: %{}
      })

    Receiver.subscribe(pid, destination)
    Receiver.listen(pid)
  end
end
