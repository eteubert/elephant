global_settings = "~/.iex.exs"
if File.exists?(global_settings), do: Code.require_file(global_settings)

Application.put_env(:elixir, :ansi_enabled, true)

IEx.configure(
  colors: [
    eval_result: [:cyan, :bright],
    eval_error: [[:red, :bright, "\n▶▶▶\n"]],
    eval_info: [:yellow, :bright]
  ],
  default_prompt:
    [
      # cursor ⇒ column 1
      "\e[G",
      :magenta,
      "%prefix",
      :yellow,
      "|",
      :magenta,
      "%counter",
      " ",
      :yellow,
      "▶",
      :reset
    ]
    |> IO.ANSI.format()
    |> IO.chardata_to_string()
)

require Logger
alias Elephant.{Message, Receiver}

defmodule H do
  def demo do
    {:ok, pid} = Elephant.start_link()
    Elephant.connect(pid, {127, 0, 0, 1}, 32770, "admin", "admin")

    callback = fn m -> IO.inspect(m, label: "demo handler") end

    Elephant.subscribe(pid, "foo.bar", callback)
  end
end
