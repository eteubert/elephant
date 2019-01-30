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

  def handle_cast(:listen, state = %{socket: socket}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, response} ->
        # - todo fetch matching subscription based on header
        # - then extract callback from the entry
        Logger.debug(response)
        handle_response(state, response)

      {:error, :closed} ->
        Logger.warn("[Elephant] Stopped listening because socket was closed.")
        {:noreply, state}
    end
  end

  @spec handle_response(map(), charlist()) :: {:noreply, map(), {:continue, :listen}}
  def handle_response(state, response)

  def handle_response(state, "") do
    {
      :noreply,
      state,
      {:continue, :listen}
    }
  end

  def handle_response(state, response) do
    state
    |> get_message(response)
    |> Message.parse()
    |> handle_message(state, response)
  end

  @spec handle_message({atom(), any()}, map(), charlist()) ::
          {:noreply, map(), {:continue, :listen}}
  defp handle_message({:incomplete, _message}, state, response) do
    Logger.info("incomplete message, continue listening...")

    {
      :noreply,
      %{state | partial_message: get_message(state, response)},
      {:continue, :listen}
    }
  end

  defp handle_message({:ok, message, more}, state, _response) do
    Logger.debug(inspect(message))
    Elephant.receive(state.consumer, message)

    handle_response(state, more)

    {:noreply, %{state | partial_message: nil}, {:continue, :listen}}
  end

  defp handle_message(_, state, response) do
    Logger.warn(
      "[Elephant] Unable to parse response: #{
        inspect(response, limit: :infinity, printable_limit: :infinity, pretty: true)
      }"
    )

    {:noreply, state, {:continue, :listen}}
  end

  def handle_continue(:listen, state) do
    GenServer.cast(self(), :listen)
    {:noreply, state}
  end

  @spec get_message(map(), charlist()) :: charlist()
  defp get_message(state, message) do
    case Map.get(state, :partial_message) do
      nil ->
        message

      partial_message ->
        partial_message ++ message
    end
  end
end
