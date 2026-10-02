defmodule IncidentRoom.MixProject do
  use Mix.Project

  def project do
    [
      app: :incident_room,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: ["lib"],
      deps: deps(),
      aliases: [
        "assets.build": ["esbuild default"],
        "assets.deploy": ["esbuild default --minify"]
      ]
    ]
  end

  def application,
    do: [mod: {IncidentRoom.Application, []}, extra_applications: [:logger, :runtime_tools, :ssl]]

  defp deps do
    [
      {:phoenix, "== 1.8.15"},
      {:phoenix_live_view, "== 1.2.12"},
      {:phoenix_html, "== 4.3.0"},
      {:ecto, "== 3.14.2"},
      {:ecto_sql, "== 3.14.0"},
      {:postgrex, "== 0.22.4"},
      {:bcrypt_elixir, "== 3.3.2"},
      {:bandit, "== 1.12.5"},
      {:jason, "== 1.4.5"},
      {:esbuild, "== 0.10.0", runtime: false},
      {:floki, "== 0.38.4", only: :test}
    ]
  end
end
