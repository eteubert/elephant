defmodule Elephant.Subscriber do
  @moduledoc """
  Keep track of subscriptions to topics or queues with callbacks.

  ## Example

      {:ok, pid} = Subscriber.start_link()
      Subscriber.subscribe(pid, "foo.bar", callback)
      Subscriber.subscribe(pid, "foo2.bar", callback)

      %{id: id, callback: cb} = Subscriber.get_subscription(pid, "foo.bar")
      
      Subscriber.unsubscribe(pid, "foo2.bar")
  """
  use GenServer

  require Logger

  # Client

  def init(args) do
    {:ok, Map.put_new(args, :subscriptions, %{})}
  end

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state)
  end

  def subscribe(pid, destination, callback) do
    GenServer.call(pid, {:subscribe, destination, callback})
  end

  def unsubscribe(pid, destination) do
    GenServer.call(pid, {:unsubscribe, destination})
  end

  def has_subscription?(pid, destination) do
    GenServer.call(pid, {:has_subscription, destination})
  end

  def get_subscription(pid, destination) do
    GenServer.call(pid, {:get_subscription, destination})
  end

  # Server

  def handle_call(
        {:has_subscription, destination},
        _from,
        state = %{subscriptions: subscriptions}
      ) do
    {
      :reply,
      Map.has_key?(subscriptions, destination),
      state
    }
  end

  def handle_call(
        {:get_subscription, destination},
        _from,
        state = %{subscriptions: subscriptions}
      ) do
    {
      :reply,
      Map.get(subscriptions, destination),
      state
    }
  end

  def handle_call(
        {:subscribe, destination, callback},
        _from,
        state = %{subscriptions: subscriptions}
      ) do
    if Map.has_key?(subscriptions, destination) do
      {:reply, {:error, "You have already subscribed to this destination"}, state}
    else
      do_subscribe(destination, callback, state)
    end
  end

  def handle_call(
        {:unsubscribe, destination},
        _from,
        state = %{subscriptions: subscriptions}
      ) do
    if !Map.has_key?(subscriptions, destination) do
      {:reply, {:error, "You are not subscribed to this destination"}, state}
    else
      {:reply, :unsubscribed, %{state | subscriptions: Map.delete(subscriptions, destination)}}
    end
  end

  defp do_subscribe(destination, callback, state = %{subscriptions: subscriptions}) do
    id = next_id(subscriptions)

    {
      :reply,
      :subscribed,
      %{
        state
        | subscriptions: Map.put(subscriptions, destination, %{id: id, callback: callback})
      }
    }
  end

  def next_id(subscriptions) do
    (subscriptions
     |> Map.values()
     |> Enum.map(& &1.id)
     |> Enum.max(fn -> 0 end)) + 1
  end
end
