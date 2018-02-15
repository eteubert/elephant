defmodule Elephant.Socket do
  alias Elephant.Message

  require Logger

  def connect(host, port) do
    {:ok, conn} = :gen_tcp.connect(host, port, [{:active, false}])
    :inet.setopts(conn, [{:recbuf, 1024}])
    {:ok, conn}
  end

  def send(conn, message = %Elephant.Message{}) do
    __MODULE__.send(conn, Message.format(message))
  end

  def send(conn, message) when is_binary(message) do
    Logger.debug(message)
    :gen_tcp.send(conn, message)
  end

  def receive(conn, length \\ 0) do
    response = :gen_tcp.recv(conn, length)

    case response do
      {:ok, response} -> Logger.debug(response)
      _ -> Logger.debug("Got response that was not :ok")
    end

    response
  end
end
