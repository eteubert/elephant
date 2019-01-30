defmodule Elephant.Message do
  @moduledoc """
  Representation of sent or received messages.

  Each message has three components:

  - command
  - list of headers
  - body

  The _command_ is an atom and only commands specified in the STOMP specification
  are allowed. Each _header_ is a 2-tuple `{"header-key", "header-value"}`. The
  _body_ is a binary.

  All commands are:

  - `:send`
  - `:message`
  - `:error`
  - `:connect`
  - `:connected`
  - `:disconnect`
  - `:receipt`
  - `:subscribe`
  - `:unsubscribe`

  """

  @enforce_keys [:command]
  defstruct command: nil, headers: [], body: nil

  alias Elephant.Message
  require Logger

  @cr <<13>>
  @lf <<10>>
  @eol @cr <> @lf
  @ascii_null <<0>>

  def format(%Message{command: :send, headers: headers, body: body}),
    do: format("SEND", headers, body)

  def format(%Message{command: :message, headers: headers, body: body}),
    do: format("MESSAGE", headers, body)

  def format(%Message{command: :error, headers: headers, body: body}),
    do: format("ERROR", headers, body)

  def format(%Message{command: :connect, headers: headers, body: nil}),
    do: format("CONNECT", headers)

  def format(%Message{command: :connected, headers: headers, body: nil}),
    do: format("CONNECTED", headers)

  def format(%Message{command: :disconnect, headers: headers, body: nil}),
    do: format("DISCONNECT", headers)

  def format(%Message{command: :receipt, headers: headers, body: nil}),
    do: format("RECEIPT", headers)

  def format(%Message{command: :subscribe, headers: headers, body: nil}),
    do: format("SUBSCRIBE", headers)

  def format(%Message{command: :unsubscribe, headers: headers, body: nil}),
    do: format("UNSUBSCRIBE", headers)

  defp format(command, headers) when is_binary(command) do
    command <> @eol <> format_headers(headers) <> @eol <> @eol <> @ascii_null
  end

  defp format(command, headers, body) when is_binary(command) do
    command <> @eol <> format_headers(headers) <> @eol <> @eol <> body <> @ascii_null
  end

  def format_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
    |> Enum.join(@eol)
  end

  def parse(message) when is_list(message) do
    message
    |> :erlang.iolist_to_binary()
    |> parse()
  end

  def parse(<<"CONNECT", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :connect})
  end

  def parse(<<"CONNECT", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :connect})
  end

  def parse(<<"CONNECTED", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :connected})
  end

  def parse(<<"CONNECTED", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :connected})
  end

  def parse(<<"DISCONNECT", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :disconnect})
  end

  def parse(<<"DISCONNECT", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :disconnect})
  end

  def parse(<<"RECEIPT", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :receipt})
  end

  def parse(<<"RECEIPT", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :receipt})
  end

  def parse(<<"MESSAGE", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :message})
  end

  def parse(<<"MESSAGE", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :message})
  end

  def parse(<<"ERROR", @eol, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :error})
  end

  def parse(<<"ERROR", @lf, tail::binary>>) do
    parse_headers(tail, [], %Message{command: :error})
  end

  def parse(_) do
    {:error, :invalid}
  end

  defp parse_headers(tail, headers, message) do
    # FIXME: I think whe issue is that the HEADERS are larger than a single TCP packet and that is not handled!
    [line, tail] =
      Regex.split(~r/\r?\n/, tail, parts: 2)
      |> case do
        [line, tail] ->
          [line, tail]

        _ ->
          raise "Unexpected line in header \ntail: #{inspect(tail)} \nheaders: #{inspect(headers)} \nmessage: #{
                  inspect(message)
                }"
      end

    cond do
      String.contains?(line, ":") ->
        parse_headers(tail, [line | headers], message)

      String.length(line) == 0 ->
        parse_body(tail, %{message | headers: normalize_headers(headers)})

      true ->
        raise "Parse error. Expected header or newline, got: #{line}"
    end
  end

  @doc """
  Checks if a header exists, by both key and value.
  """
  def has_header(headers, {k, v}) when is_integer(v) do
    has_header(headers, {k, to_string(v)})
  end

  def has_header(%Message{headers: headers}, {k, v}) do
    Enum.any?(headers, fn header -> header == {k, v} end)
  end

  @doc """
  Get header by key.

  Returns `{:ok, value}` or `{:error, :notfound}` if the header does not exist.
  """
  def get_header(%Message{headers: headers}, key) do
    headers
    |> Enum.find(fn header -> elem(header, 0) == key end)
    |> case do
      {_, value} -> {:ok, value}
      nil -> {:error, :notfound}
    end
  end

  @doc """
  Turn list of raw header lines into key value pairs.

    iex> Elephant.Message.normalize_headers([<<"message-id:ID", 92, 99, "b39dd">>])
    [{"message-id", "ID:b39dd"}]
  """
  def normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.reverse()
    |> Enum.map(fn header ->
      [k, v] = Regex.split(~r{:}, header, parts: 2)
      {k, apply_value_decoding(v)}
    end)
  end

  @doc """
  Apply "Value Decoding" for header values.

  See https://stomp.github.io/stomp-specification-1.2.html#Valuea_Encoding

  ## Examples

    iex> Elephant.Message.apply_value_decoding(<<"foo", 92, 92, "bar">>)
    <<"foo", 92, "bar">>

    iex> Elephant.Message.apply_value_decoding(<<"foo", 92, 99, "bar">>)
    "foo:bar"

    iex> Elephant.Message.apply_value_decoding(<<"foo", 92, 110, "bar">>)
    <<"foo", 10, "bar">>

    iex> Elephant.Message.apply_value_decoding(<<"foo", 92, 114, "bar">>)
    <<"foo", 13, "bar">>
  """
  def apply_value_decoding(value) when is_binary(value) do
    apply_value_decoding(String.to_charlist(value), [])
  end

  def apply_value_decoding(value) when is_list(value) do
    apply_value_decoding(value, [])
  end

  defp apply_value_decoding([92 | [92 | tail]], result) do
    apply_value_decoding(tail, [92 | result])
  end

  defp apply_value_decoding([92 | [99 | tail]], result) do
    apply_value_decoding(tail, [?: | result])
  end

  defp apply_value_decoding([92 | [110 | tail]], result) do
    apply_value_decoding(tail, [@lf | result])
  end

  defp apply_value_decoding([92 | [114 | tail]], result) do
    apply_value_decoding(tail, [@cr | result])
  end

  defp apply_value_decoding([other | tail], result) do
    apply_value_decoding(tail, [other | result])
  end

  defp apply_value_decoding([], result) do
    Enum.reverse(result) |> to_string
  end

  defp parse_body(tail, message) do
    case read_until_zero(tail) do
      {:ok, body, more} ->
        more = more |> skip_newlines

        message =
          case String.length(body) do
            0 -> message
            _ -> %{message | body: body}
          end

        {:ok, message, more}

      {:nozero, body} ->
        message =
          case String.length(body) do
            0 -> message
            _ -> %{message | body: body}
          end

        {:incomplete, message}
    end
  end

  @doc ~S"""
  Splits a string into two at the first zero-byte.

  ## Examples

      iex> Elephant.Message.read_until_zero(<<65, 66, 0, 67, 68>>)
      {:ok, "AB", "CD"}

      iex> Elephant.Message.read_until_zero(<<65, 66, 0>>)
      {:ok, "AB", ""}

      iex> Elephant.Message.read_until_zero(<<0, 67, 68>>)
      {:ok, "", "CD"}

      iex> Elephant.Message.read_until_zero(<<65, 66>>)
      {:nozero, "AB"}
  """
  def read_until_zero(string), do: _read_until_zero([], :binary.bin_to_list(string))

  defp _read_until_zero(body, [0 | more]),
    do: {:ok, to_string(Enum.reverse(body)), to_string(more)}

  defp _read_until_zero(body, []), do: {:nozero, to_string(Enum.reverse(body))}

  defp _read_until_zero(body, [codepoint | more]), do: _read_until_zero([codepoint | body], more)

  @doc ~S"""
  Removes CR / CRLF at the beginning of the string.

  ## Examples

      iex> Elephant.Message.skip_newlines("\n\n\nHello")
      "Hello"

      iex> Elephant.Message.skip_newlines("Hello")
      "Hello"

      iex> Elephant.Message.skip_newlines("\r\n\r\nHello")
      "Hello"
  """
  def skip_newlines(<<@lf, tail::binary>>), do: skip_newlines(tail)
  def skip_newlines(<<@cr, @lf, tail::binary>>), do: skip_newlines(tail)
  def skip_newlines(string), do: string
end
