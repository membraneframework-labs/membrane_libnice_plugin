defmodule ExampleProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_project,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:membrane_ice_plugin, path: "../.."},
      {:membrane_file_plugin, "~> 0.5.0"},
      {:membrane_hackney_plugin, "~> 0.4.0"}
    ]
  end
end
