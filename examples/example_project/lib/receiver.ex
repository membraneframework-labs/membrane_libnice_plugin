defmodule Example.Receiver do
  use Membrane.Pipeline

  require Membrane.Logger

  alias Example.Common
  alias Membrane.File

  @impl true
  def handle_init(_) do
    children = %{
      ice: %Membrane.ICE.Bin{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: false,
        handshake_module: Membrane.ICE.Handshake.Default,
      },
      sink: %File.Sink{
        location: "/tmp/ice-recv.h264"
      }
    }

    pad = Pad.ref(:output, 1)
    links = [link(:ice) |> via_out(pad) |> to(:sink)]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
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
