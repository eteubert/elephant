defmodule Elephant.Receiver do
  use GenServer

  require Logger
  alias Elephant.Message

  # Client

  def init(args) do
    args = Map.put(args, :partial_message, nil)
    {:ok, args}
  end

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state)
  end

  def listen(pid) do
    GenServer.cast(pid, :listen)
  end

  def stop(server) do
    GenServer.stop(server)
  end

  # Server

  def handle_cast(:listen, state = %{socket: socket, consumer: consumer}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, response} ->
        # - todo fetch matching subscription based on header
        # - then extract callback from the entry
        Logger.debug(response)
        handle_response(state, consumer, response)

      {:error, :closed} ->
        Logger.warn("[Elephant] Stopped listening because socket was closed.")
        {:noreply, state}
    end
  end

  def handle_continue(:listen, state) do
    GenServer.cast(self(), :listen)
    {:noreply, state}
  end

  # todo: don't pass consumer around in function head, leave it in state
  # todo: handle empty "more" graciously
  @spec handle_response(map(), pid(), charlist()) :: {:noreply, map(), {:continue, :listen}}
  def handle_response(state, consumer, response) do
    raw_message =
      case Map.get(state, :partial_message) do
        nil ->
          response

        partial_message ->
          partial_message ++ response
      end

    case Message.parse(raw_message) do
      {:incomplete, _message} ->
        Logger.info("incomplete message, continue listening...")

        {
          :noreply,
          %{state | partial_message: raw_message},
          {:continue, :listen}
        }

      # 1> I don't know if I need to :listen again here or what this is about
      # 2> I should just store incomplete messages in ETS or GenServer state
      # 3> Then when a new msg comes in, see if an incomplete is there and concat before parsing
      # 4> Then ensure this works recursively, if a message is split in 3+ parts

      {:ok, message, more} ->
        Logger.debug(inspect(message))
        Elephant.receive(consumer, message)

        IO.inspect(more, label: more)
        handle_response(state, consumer, more)

        {:noreply, %{state | partial_message: nil}, {:continue, :listen}}

      _ ->
        Logger.warn(
          "[Elephant] Unable to parse response: #{
            inspect(response, limit: :infinity, printable_limit: :infinity, pretty: true)
          }"
        )

        {:noreply, state, {:continue, :listen}}
    end
  end
end
