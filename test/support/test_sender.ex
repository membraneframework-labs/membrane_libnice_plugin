defmodule Membrane.ICE.Support.TestSender do
  @moduledoc false

  use Membrane.Pipeline

  alias Membrane.Hackney

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      ice: %Membrane.ICE.Bin{
        stun_servers: [%{server_addr: "stun1.l.google.com", server_port: 19_302}],
        controlling_mode: true,
        handshake_module: opts[:handshake_module],
        handshake_opts: opts[:handshake_opts]
      },
      source: %Hackney.Source{
        location: "https://membraneframework.github.io/static/video-samples/test-video.h264"
      }
    }

    pad = Pad.ref(:input, 1)
    links = [link(:source) |> via_out(:output) |> via_in(pad) |> to(:ice)]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end
end
