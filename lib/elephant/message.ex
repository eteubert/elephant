defmodule Elephant.Message do
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

  defp parse_headers(tail, headers, message) do
    [line, tail] = Regex.split(~r/\r?\n/, tail, parts: 2)

    cond do
      String.contains?(line, ":") ->
        parse_headers(tail, [line | headers], message)

      String.length(line) == 0 ->
        parse_body(tail, %{message | headers: normalize_headers(headers)})

      true ->
        raise "Parse error. Expected header or newline, got: #{line}"
    end
  end

  def has_header(headers, {k, v}) when is_integer(v) do
    has_header(headers, {k, to_string(v)})
  end

  def has_header(%Message{headers: headers}, {k, v}) do
    Enum.any?(headers, fn header -> header == {k, v} end)
  end

  def normalize_headers(headers) do
    headers
    |> Enum.reverse()
    |> Enum.map(fn header ->
      [k, v] = Regex.split(~r{:}, header, parts: 2)
      {k, v}
    end)
  end

  defp parse_body(tail, message) do
    {body, more} = read_until_zero(tail)

    more = more |> skip_newlines

    message =
      case String.length(body) do
        0 -> message
        _ -> %{message | body: body}
      end

    {:ok, message, more}
  end

  @doc ~S"""
  Splits a string into two at the first zero-byte.

  ## Examples

      iex> Elephant.Message.read_until_zero(<<65, 66, 0, 67, 68>>)
      {"AB", "CD"}

      iex> Elephant.Message.read_until_zero(<<65, 66, 0>>)
      {"AB", ""}

      iex> Elephant.Message.read_until_zero(<<0, 67, 68>>)
      {"", "CD"}

      iex> Elephant.Message.read_until_zero(<<65, 66>>)
      {"AB", ""}
  """
  def read_until_zero(string), do: _read_until_zero([], :binary.bin_to_list(string))
  defp _read_until_zero(body, [0 | more]), do: {to_string(Enum.reverse(body)), to_string(more)}
  defp _read_until_zero(body, []), do: {to_string(Enum.reverse(body)), ""}
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
