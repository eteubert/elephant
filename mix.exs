defmodule Elephant.MixProject do
  use Mix.Project

  def project do
    [
      app: :elephant,
      description: "A STOMP client to listen to, for example, AMQ.",
      version: "0.2.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      source_url: "https://github.com/eteubert/elephant",
      docs: [
        main: "Elephant"
      ]
    ]
  end

  defp package() do
    [
      maintainers: ["Eric Teubert"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/eteubert/elephant"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Elephant.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_guard, "~> 1.1.1", only: :dev},
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end
end
