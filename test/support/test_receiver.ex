defmodule Membrane.ICE.Support.TestReceiver do
  @moduledoc false

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
      },
      sink: %File.Sink{
        location: opts[:file_path]
      }
    }

    pad = Pad.ref(:output, 1)
    links = [link(:source) |> via_out(pad) |> to(:sink)]

    spec = %ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(
        {:component_state_ready, component_id, handshake_data},
        _from,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("Handshake data #{inspect(handshake_data)}")
    new_state = Map.put(state, :component_id, component_id)
    {:ok, new_state}
  end

  @impl true
  def handle_notification(_other, _from, _ctx, state) do
    {:ok, state}
  end
end
