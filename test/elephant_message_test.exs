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

  test "parses messages" do
    message = "CONNECT\r\nkey:value\r\n\r\ntest" <> <<0>>

    assert Message.parse(message) == %Message{
             command: :connect,
             headers: [{"key", "value"}],
             body: "test"
           }
  end

  test "parses messages with multiple headers" do
    message = "CONNECT\r\nkey:value\r\nkey2:value2\r\n\r\ntest" <> <<0>>

    assert Message.parse(message) == %Message{
             command: :connect,
             headers: [{"key", "value"}, {"key2", "value2"}],
             body: "test"
           }
  end

  test "parses messages with LF but no CR" do
    message = "CONNECT\nkey:value\n\ntest" <> <<0>>

    assert Message.parse(message) == %Message{
             command: :connect,
             headers: [{"key", "value"}],
             body: "test"
           }
  end

  test "parses messages without headers" do
    message = "CONNECT\r\n\r\n" <> <<0>>

    assert Message.parse(message) == %Message{
             command: :connect,
             headers: []
           }
  end
end
