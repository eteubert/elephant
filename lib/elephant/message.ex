defmodule Elephant.Message do
  @enforce_keys [:command]
  defstruct command: nil, headers: [], body: nil

  alias Elephant.Message

  @eol <<13, 10>>
  @ascii_null <<0>>

  def format(%Message{command: :send, headers: headers, body: body}),
    do: format("SEND", headers, body)

  def format(%Message{command: :message, headers: headers, body: body}),
    do: format("MESSAGE", headers, body)

  def format(%Message{command: :error, headers: headers, body: body}),
    do: format("ERROR", headers, body)

  def format(%Message{command: :connect, headers: headers, body: nil}),
    do: format("CONNECT", headers)

  defp format(command, headers) when is_binary(command) do
    command <> @eol <> headers(headers) <> @eol <> @eol <> @ascii_null
  end

  defp format(command, headers, body) when is_binary(command) do
    command <> @eol <> headers(headers) <> @eol <> @eol <> body <> @ascii_null
  end

  def headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
    |> Enum.join(@eol)
  end
end
