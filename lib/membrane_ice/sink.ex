defmodule Membrane.ICE.Sink do
  use Membrane.Sink

  require Unifex.CNode
  require Membrane.Logger

  alias Membrane.Buffer
  alias Membrane.ICE.Common

  def_options stun_servers: [
                type: [:string],
                default: [],
                description: "List of stun servers in form of ip:port"
              ],
              turn_servers: [
                type: [:string],
                default: [],
                description: "List of turn servers in form of ip:port:proto:username:passwd"
              ],
              controlling_mode: [
                type: :integer,
                default: 0,
                description: "0 for FALSE, 1 for TRUE"
              ]

  def_input_pad :input,
    availability: :always,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  @impl true
  def handle_init(%__MODULE__{} = options) do
    %__MODULE__{
      stun_servers: stun_servers,
      turn_servers: turn_servers,
      controlling_mode: controlling_mode
    } = options

    {:ok, cnode} = Unifex.CNode.start_link(:native)
    :ok = Unifex.CNode.call(cnode, :init, [stun_servers, turn_servers, controlling_mode])

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
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_other(msg, context, state) do
    Common.handle_ice_message(msg, context, state)
  end

  def handle_write(
        :input,
        %Buffer{payload: payload, metadata: metadata},
        _context,
        %{cnode: cnode} = state
      ) do
    stream_id = Map.get(metadata, :stream_id, nil)
    component_id = Map.get(metadata, :component_id, nil)

    if !stream_id || !component_id do
      {{:error, :no_stream_or_component_id}, state}
    else
      case Unifex.CNode.call(cnode, :send_payload, [stream_id, component_id, payload]) do
        :ok -> {{:ok, demand: :input}, state}
        {:error, cause} -> {{:error, cause}, state}
      end
    end
  end
end
