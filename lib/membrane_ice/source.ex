defmodule Membrane.ICE.Source do
  use Membrane.Source

  require Unifex.CNode

  alias Membrane.Buffer
  alias Membrane.ICE.Common

  def_output_pad :output,
    availability: :always,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(_options) do
    {:ok, cnode} = Unifex.CNode.start_link(:native)
    :ok = Unifex.CNode.call(cnode, :init)

    state = %{
      cnode: cnode
    }

    {:ok, state}
  end

  @impl true
  def handle_other(
        {:new_selected_pair, _stream_id, _component_id, _lfoundation, _rfoundation} = msg,
        _context,
        state
      ) do
    {{:ok, notify: msg}, state}
  end

  @impl true
  def handle_other(
        {:ice_payload, stream_id, component_id, payload},
        %{playback_state: :playing},
        state
      ) do
    metadata = %{:stream_id => stream_id, :component_id => component_id}
    actions = [buffer: {:output, %Buffer{payload: payload, metadata: metadata}}]
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other(msg, context, state) do
    Common.handle_ice_message(msg, context, state)
  end
end
