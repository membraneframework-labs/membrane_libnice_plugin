defmodule Membrane.ICE.Support.TestSender do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.Hackney

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      ice: %Membrane.ICE.Bin{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: true,
        handshake_module: opts[:handshake_module],
        handshake_opts: opts[:handshake_opts]
      },
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    links = [
      link(:source) |> via_out(:output) |> via_in(:input, options: [component_id: 1]) |> to(:ice)
    ]

    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, %{}}
  end
end
