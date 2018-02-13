defmodule Elephant do
  @moduledoc """
  Elephant: A STOMP client.

  Example:

    {:ok, conn} = Elephant.connect({127,0,0,1}, 32770, "admin", "admin")
    Elephant.subscribe(conn, "/test/me")
  """

  require Logger
  alias Elephant.Message
  alias Elephant.Receiver

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

  def subscribe(conn, destination) do
    {:ok, pid} = Receiver.start_link(conn)
    Receiver.subscribe(pid, destination)
    Receiver.listen(pid)
  end
end
