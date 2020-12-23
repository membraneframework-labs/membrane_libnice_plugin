# Membrane ICE plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_ice_plugin.svg)](https://hex.pm/packages/membrane_ice_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ice_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_ice_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_ice_plugin)

Membrane plugin for ICE protocol.

It enables establishing connection, sending and receiving messages using ICE protocol.

This package uses [ex_libnice] and is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_ice_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_ice_plugin, "~> 0.2.1"}
  ]
end
```

## Usage

See [example_project] for example usage or refer to
[hex.pm](https://hex.pm/packages/membrane_ice_plugin) for more details about how to interact with
Sink and Source.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_ice)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_ice)

Licensed under the [Apache License, Version 2.0](LICENSE)

[libnice]: https://libnice.freedesktop.org/
[ex_libnice]: https://github.com/membraneframework/ex_libnice
[example_project]: https://github.com/membraneframework/membrane_ice_plugin/tree/master/examples/example_project
