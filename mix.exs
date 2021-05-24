defmodule Membrane.ICE.Plugin.Mixfile do
  use Mix.Project

  @version "0.5.0"
  @github_url "https://github.com/membraneframework/membrane_ice_plugin"

  def project do
    [
      app: :membrane_ice_plugin,
      version: @version,
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "Membrane plugin for ICE protocol",
      package: package(),

      # docs
      name: "Membrane ICE plugin",
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
      {:membrane_core,
       github: "membraneframework/membrane_core", branch: "develop", override: true},
      {:unifex, "~> 0.4.0"},
      {:bunch, "~> 1.3.0"},
      {:ex_libnice, "~> 0.4.0"},
      {:membrane_funnel_plugin, "~> 0.1.0"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:membrane_file_plugin, "~> 0.5.0", only: :test},
      {:membrane_hackney_plugin, "~> 0.4.0", only: :test}
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
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.ICE]
    ]
  end
end
