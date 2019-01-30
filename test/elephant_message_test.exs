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

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key", "value"}],
                body: "test"
              }, ""}
  end

  # test "parses messages with 'Value Encoding' headers" do
  #   message =
  #     "CONNECT\r\nmessage-id:ID\c27f59e3a2e7d-41496-1511347079793-1\c89\c1\c1\c1\r\n\r\ntest" <>
  #       <<0>>

  #   assert Message.parse(message) ==
  #            {:ok,
  #             %Message{
  #               command: :connect,
  #               headers: [{"message-id", "ID:27f59e3a2e7d-41496-1511347079793-1:89:1:1:1"}],
  #               body: "test"
  #             }, ""}
  # end

  test "parses headers with empty value" do
    message = "CONNECT\r\nkey1:value1\r\nkey2:\r\nkey3:value3\r\n\r\ntest" <> <<0>>

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key1", "value1"}, {"key2", ""}, {"key3", "value3"}],
                body: "test"
              }, ""}
  end

  test "parses messages with LF after zero byte" do
    message = "CONNECT\r\nkey:value\r\n\r\ntest" <> <<0>> <> "\n"

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key", "value"}],
                body: "test"
              }, ""}
  end

  test "parses messages with CRLF after zero byte" do
    message = "CONNECT\r\nkey:value\r\n\r\ntest" <> <<0>> <> "\r\n"

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key", "value"}],
                body: "test"
              }, ""}
  end

  test "parses messages with multiple headers" do
    message = "CONNECT\r\nkey:value\r\nkey2:value2\r\n\r\ntest" <> <<0>>

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key", "value"}, {"key2", "value2"}],
                body: "test"
              }, ""}
  end

  test "parses messages with LF but no CR" do
    message = "CONNECT\nkey:value\n\ntest" <> <<0>>

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: [{"key", "value"}],
                body: "test"
              }, ""}
  end

  test "parses messages without headers" do
    message = "CONNECT\r\n\r\n" <> <<0>>

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :connect,
                headers: []
              }, ""}
  end

  test "parses incomplete message" do
    message = "MESSAGE\r\nkey:value\r\n\r\ntest"

    assert Message.parse(message) ==
             {:incomplete,
              %Message{
                command: :message,
                headers: [{"key", "value"}],
                body: "test"
              }}
  end

  # think where I should handle multi part messages. here or maybe one abstaction layer higher.
  # don't pass incomplete messages to client but gather and concatenate until we have a complete
  # message.
  # test "parses multi part message"

  test "parses invalid message" do
    message = "invalid"

    assert Message.parse(message) == {:error, :invalid}
  end

  test "parses error message" do
    message = "ERROR\r\ncontent-type:text/plain\r\n\r\nthis is the body" <> <<0>>

    assert Message.parse(message) ==
             {:ok,
              %Message{
                command: :error,
                headers: [{"content-type", "text/plain"}],
                body: "this is the body"
              }, ""}
  end

  test "parses multiple messages" do
    message =
      "MESSAGE\nkey:value\n\ntest" <>
        <<0>> <> <<13, 10>> <> "MESSAGE\nkey2:value2\n\ntest2" <> <<0>>

    msg1 = %Message{
      command: :message,
      headers: [{"key", "value"}],
      body: "test"
    }

    msg2 = %Message{
      command: :message,
      headers: [{"key2", "value2"}],
      body: "test2"
    }

    {:ok, return1, rest1} = Message.parse(message)
    {:ok, return2, ""} = Message.parse(rest1)

    assert return1 == msg1
    assert return2 == msg2
  end

  test "has_header" do
    msg = %Message{
      command: :message,
      headers: [{"key", "value"}]
    }

    assert Message.has_header(msg, {"key", "value"})
    assert !Message.has_header(msg, {"key", "wrong"})
  end

  test "has_header with integer value" do
    msg = %Message{
      command: :message,
      headers: [{"key", "23"}]
    }

    assert Message.has_header(msg, {"key", 23})
  end
end
