defmodule Elephant do
  @moduledoc ~S"""
  Elephant: A STOMP client.

  Example:

      {:ok, conn} = Elephant.connect({127,0,0,1}, 61613, "admin", "admin")

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

      Elephant.subscribe(conn, "foo.bar", callback)

      # when you are finished, disconnect
      Elephant.disconnect(conn)
  """

  require Logger
  alias Elephant.Message
  alias Elephant.Receiver

  @doc """
  Connect to server.

  Returns `{:ok, conn}` or `{:error, message}`.
  """
  def connect(host, port, login, password) do
    message =
      connect_message(login, password)
      |> Message.format()

    Logger.debug(message)

    {:ok, conn} = :gen_tcp.connect(host, port, [{:active, false}])
    :inet.setopts(conn, [{:recbuf, 1024}])
    :gen_tcp.send(conn, message)
    {:ok, response} = :gen_tcp.recv(conn, 0)

    Logger.debug(response)

    {:ok, response_message, _} = Message.parse(response)

    case response_message.command do
      :connected -> {:ok, conn}
      _ -> {:error, response_message}
    end
  end

  @doc """
  Disconnects from server.

  Returns `{:ok, :disconnected}` or `{:error, :disconnect_failed, message}`.
  """
  def disconnect(conn) do
    receipt_id = Enum.random(1000..1_000_000)

    message =
      disconnect_message(receipt_id)
      |> Message.format()

    Logger.debug(message)

    :gen_tcp.send(conn, message)

    case :gen_tcp.recv(conn, 0) do
      {:error, :closed} ->
        {:ok, :disconnected}

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
  """
  def subscribe(conn, destination, callback) do
    {:ok, pid} = Receiver.start_link(%{conn: conn, callback: callback})
    Receiver.subscribe(pid, destination)
    Receiver.listen(pid)
  end
end
