defmodule ElephantSubscriberTest do
  use ExUnit.Case

  alias Elephant.Subscriber

  require Logger

  # doctest Elephant.Subscriber

  test "keeps track of subscriptions" do
    {:ok, pid} = Subscriber.start_link()
    Subscriber.subscribe(pid, "foo.bar", 42)
    Subscriber.subscribe(pid, "foo2.bar", 43)

    assert Subscriber.has_subscription?(pid, "foo.bar")
    assert Subscriber.has_subscription?(pid, "foo2.bar")
    assert !Subscriber.has_subscription?(pid, "foo3.bar")
  end

  test "do not allow double subscriptions" do
    {:ok, pid} = Subscriber.start_link()
    Subscriber.subscribe(pid, "foo.bar", 42)
    {mode, _msg} = Subscriber.subscribe(pid, "foo.bar", 43)

    assert mode == :error
    assert Subscriber.get_subscription(pid, "foo.bar").callback == 42
  end

  test "delete subscriptions" do
    {:ok, pid} = Subscriber.start_link()
    Subscriber.subscribe(pid, "foo.bar", 42)

    assert Subscriber.has_subscription?(pid, "foo.bar")

    Subscriber.unsubscribe(pid, "foo.bar")

    assert !Subscriber.has_subscription?(pid, "foo.bar")
  end
end
