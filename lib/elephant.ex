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

    {:ok, sock} = :gen_tcp.connect(host, port, [{:active, false}])
    :inet.setopts(sock, [{:recbuf, 1024}])
    :gen_tcp.send(sock, message)
    {:ok, response} = :gen_tcp.recv(sock, 0)

    Logger.debug(response)

    response_message =
      response
      |> :erlang.iolist_to_binary()
      |> Message.parse()

    case response_message.command do
      :connected -> {:ok, sock}
      _ -> {:error, response_message}
    end
  end
end
