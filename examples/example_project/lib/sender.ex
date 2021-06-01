defmodule Example.Sender do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Example.Common
  alias Membrane.Hackney

  @impl true
  def handle_init(_) do
    children = %{
      ice: %Membrane.ICE.Bin{
        stream_name: "video",
        stun_servers: [
          %{
            server_addr: {64, 233, 161, 127},
            server_port: 19302
          }
        ],
        controlling_mode: true,
        handshake_module: Membrane.ICE.Handshake.Default
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

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, forward: [ice: :gather_candidates]}, state}
  end

  @impl true
  def handle_notification(other, from, ctx, state) do
    Common.handle_notification(other, from, ctx, state)
  end

  @impl true
  def handle_other({:set_remote_credentials, remote_credentials}, _ctx, state) do
    {{:ok, forward: {:ice, {:set_remote_credentials, remote_credentials}}}, state}
  end

  @impl true
  def handle_other({:set_remote_candidate, candidate}, _ctx, state) do
    {{:ok, forward: {:ice, {:set_remote_candidate, candidate, 1}}}, state}
  end

  @impl true
  def handle_other(other, _ctx, state) do
    {{:ok, forward: {:ice, other}}, state}
  end
end
