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

  def normalize_headers(headers) do
    headers
    |> Enum.reverse()
    |> Enum.map(fn header ->
      [k, v] = Regex.split(~r{:}, header, parts: 2)
      {k, v}
    end)
  end

  defp parse_body(tail, message) do
    tail_size = byte_size(tail)

    # if tail size is < 3 there is no body
    # TODO should still verify that the tail is valid
    if tail_size < 3 do
      message
    else
      body_size = tail_size - 1
      <<body::binary-size(body_size), 0, _rest::binary>> = tail

      # todo verify that _rest is empty or newline

      %{message | body: body}
    end
  end
end
