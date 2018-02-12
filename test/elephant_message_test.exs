defmodule ElephantMessageTest do
  use ExUnit.Case

  alias Elephant.Message

  doctest Elephant.Message

  test "prints messages" do
    message = %Message{
      command: :send,
      headers: [{"key", "value"}],
      body: "test"
    }

    str = Message.format(message)

    assert str == "SEND\r\nkey:value\r\n\r\ntest" <> <<0>>
  end

  test "prints connect message" do
    message = %Message{
      command: :connect,
      headers: [{"key", "value"}]
    }

    str = Message.format(message)

    assert str == "CONNECT\r\nkey:value\r\n\r\n" <> <<0>>
  end
end
