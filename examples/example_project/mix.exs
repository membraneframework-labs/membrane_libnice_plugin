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
      {:membrane_core, git: "https://github.com/membraneframework/membrane_core.git", branch: "master", override: true},
      {:membrane_ice, path: "../.."},
      {:membrane_element_file,
       git: "https://github.com/membraneframework/membrane-element-file", branch: "master"}
    ]
  end
end
