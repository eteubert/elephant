defmodule Elephant do
  @moduledoc """
  Elephant: A STOMP client.

  Example:

      {:ok, conn} = Elephant.connect({127,0,0,1}, 61613, "admin", "admin")

      callback = fn
        %Elephant.Message{command: :message, headers: headers, body: body} ->
          Logger.info(["Received MESSAGE", "\\nheaders: ", inspect(headers), "\\nbody: ", inspect(body)])

        %Elephant.Message{command: :error, headers: headers, body: body} ->
          Logger.error(["Received ERROR", "\\nheaders: ", inspect(headers), "\\nbody: ", inspect(body)])

        %Elephant.Message{command: cmd, headers: headers, body: body} ->
          Logger.error([
            "Received unknown command: ", cmd, 
            "\\nheaders: ",
            inspect(headers),
            "\\nbody: ",
            inspect(body)
          ])
      end

      Elephant.subscribe(conn, "foo.bar", callback)
  """

  require Logger
  alias Elephant.Message
  alias Elephant.Receiver

  @doc """
  Connect to server, returns socket.
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

  @doc """
  Subscribe to a topic or queue.
  """
  def subscribe(conn, destination, callback) do
    {:ok, pid} = Receiver.start_link(%{conn: conn, callback: callback})
    Receiver.subscribe(pid, destination)
    Receiver.listen(pid)
  end
end
