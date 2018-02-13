defmodule Elephant do
  @moduledoc """
  Elephant: A STOMP client.
  """

  require Logger
  alias Elephant.Message

  @doc """
  Connect to server, returns socket.

  ## Examples

      iex> Elephant.hello
      :world

  """
  def connect(host, port, login, password) do
    message =
      %Message{
        command: :connect,
        headers: [
          {"accept-version", "1.2"},
          {"host", "localhost"},
          {"login", login},
          {"password", password}
        ]
      }
      |> Message.format()

    Logger.debug(message)

    {:ok, conn} = :gen_tcp.connect(host, port, [{:active, false}])
    :inet.setopts(conn, [{:recbuf, 1024}])
    :gen_tcp.send(conn, message)
    {:ok, response} = :gen_tcp.recv(conn, 0)

    Logger.debug(response)

    response_message =
      response
      |> :erlang.iolist_to_binary()
      |> Message.parse()

    case response_message.command do
      :connected -> {:ok, conn}
      _ -> {:error, response_message}
    end
  end

  def subscribe(conn, destination, opts) do
    message =
      %Message{
        command: :subscribe,
        headers:
          [
            {"destination", destination},
            {"ack", "auto"},
            {"id", "42"}
          ] ++ opts
      }
      |> Message.format()

    Logger.debug(message)

    :gen_tcp.send(conn, message)

    # TODO: once received, receive again until unsubscribe
    # TODO: register message handler

    {:ok, response} = :gen_tcp.recv(conn, 0)
    Logger.debug(response)

    response_message =
      response
      |> :erlang.iolist_to_binary()
      |> Message.parse()

    Logger.debug(inspect(response_message))

    conn
  end
end
