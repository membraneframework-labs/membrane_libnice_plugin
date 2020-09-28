defmodule Membrane.ICE.Support.TestReceiver do
  use Membrane.Pipeline

  alias Membrane.Element.File

  require Membrane.Logger

  @impl true
  def handle_init(opts) do
    children = %{
      source: %Membrane.ICE.Source{
        stun_servers: ["64.233.161.127:19302"],
        controlling_mode: false,
        handshake_module: opts[:handshake_module],
        handshake_opts: opts[:handshake_opts]
      }
    }

    spec = %ParentSpec{
      children: children
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    children = %{
      sink: %File.Sink{
        location: "/tmp/ice-recv.h264"
      }
    }

    pad = Pad.ref(:output, {state.stream_id, state.component_id})
    links = [link(:source) |> via_out(pad) |> to(:sink)]
    spec = %ParentSpec{children: children, links: links}
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_notification({:component_state_ready, stream_id, component_id}, _from, _ctx, _state) do
    new_state = %{:stream_id => stream_id, :component_id => component_id}
    {:ok, new_state}
  end

  @impl true
  def handle_notification(_other, _from, _ctx, state) do
    {:ok, state}
  end
end
