defmodule Membrane.ICE.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane_ice"

  def project do
    [
      app: :membrane_ice,
      version: @version,
      elixir: "~> 1.10.4",
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description:
        "Interactive Connectivity Establishment (ICE) implementation for Membrane Multimedia Framework",
      package: package(),

      # docs
      name: "Membrane: ICE",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, git: "https://github.com/membraneframework/membrane_core.git", branch: "master", override: true},
#      {:unifex,
#       git: "https://github.com/membraneframework/unifex.git",
#       branch: "implement-cnode-string",
#       override: true},
      {:unifex, path: "/home/michal/Repos/unifex", override: true},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs", "bundlex.exs", "c_src"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.ICE]
    ]
  end
end
