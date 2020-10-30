# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Membrane.ICE.Common do
  @moduledoc false

  # Module containing common behaviour for Sink and Source modules.

  alias Membrane.ICE.Handshake

  require Unifex.CNode
  require Membrane.Logger

  defmodule State do
    @moduledoc false

    @type handshake_state :: :in_progress | :finished
    @type handshake_data :: term()
    @type component_id :: integer()

    @type t :: %__MODULE__{
            ice: pid(),
            controlling_mode: boolean(),
            stream_id: integer(),
            n_components: integer(),
            stream_name: String.t(),
            handshakes: %{
              component_id() => {Handshake.ctx(), handshake_state(), handshake_data()}
            },
            handshake_module: Handshake.t(),
            handshake_opts: list(),
            connections: MapSet.t()
          }
    defstruct ice: nil,
              controlling_mode: false,
              stream_id: nil,
              n_components: 1,
              stream_name: "",
              handshakes: %{},
              handshake_module: Handshake.Default,
              handshake_opts: [],
              connections: MapSet.new()
  end

  def handle_stopped_to_prepared(_ctx, state) do
    %State{
      ice: ice,
      n_components: n_components,
      stream_name: stream_name,
      handshake_module: handshake_module,
      handshake_opts: handshake_opts
    } = state

    case ExLibnice.add_stream(ice, n_components, stream_name) do
      {:ok, stream_id} ->
        handshakes =
          1..n_components
          |> Map.new(fn component_id, acc ->
            {:ok, ctx} = handshake_module.init(handshake_opts)
            Map.put(acc, component_id, {ctx, :in_progress, nil})
          end)

        {:ok, %State{state | stream_id: stream_id, handshakes: handshakes}}

      {:error, cause} ->
        {{:error, cause}, state}
    end
  end

  def handle_ice_message(:generate_local_sdp, _ctx, %State{ice: ice} = state) do
    {:ok, local_sdp} = ExLibnice.generate_local_sdp(ice)

    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp

    Membrane.Logger.debug("local sdp: #{inspect(local_sdp)}")

    {{:ok, notify: {:local_sdp, local_sdp}}, state}
  end

  def handle_ice_message({:parse_remote_sdp, sdp}, _ctx, %State{ice: ice} = state) do
    case ExLibnice.parse_remote_sdp(ice, sdp) do
      {:ok, added_cand_num} ->
        {{:ok, notify: {:parse_remote_sdp_ok, added_cand_num}}, state}

      {:error, cause} ->
        {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        :get_local_credentials,
        _ctx,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.get_local_credentials(ice, stream_id) do
      {:ok, credentials} -> {{:ok, notify: {:local_credentials, credentials}}, state}
      {:error, cause} -> {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_credentials, credentials},
        _ctx,
        %{ice: ice, stream_id: stream_id} = state
      ) do
    result = ExLibnice.set_remote_credentials(ice, credentials, stream_id)
    {result, state}
  end

  def handle_ice_message(:gather_candidates, _ctx, %State{ice: ice, stream_id: stream_id} = state) do
    case ExLibnice.gather_candidates(ice, stream_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        :peer_candidate_gathering_done,
        _ctx,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.peer_candidate_gathering_done(ice, stream_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_candidate, candidate, component_id},
        _ctx,
        %State{ice: ice, stream_id: stream_id} = state
      ) do
    case ExLibnice.set_remote_candidate(ice, candidate, stream_id, component_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:new_candidate_full, _cand} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:new_remote_candidate_full, _cand} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:candidate_gathering_done, _stream_id} = msg, _ctx, state) do
    Membrane.Logger.debug("#{inspect(msg)}")

    {{:ok, notify: :candidate_gathering_done}, state}
  end

  def handle_ice_message(
        {:new_selected_pair, _stream_id, component_id, lfoundation, rfoundation} = msg,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("#{inspect(msg)}")

    {{:ok, notify: {:new_selected_pair, component_id, lfoundation, rfoundation}}, state}
  end

  def handle_ice_message({:component_state_failed, _stream_id, component_id}, _ctx, state) do
    Membrane.Logger.warn("Component #{component_id} state FAILED")
    {:ok, state}
  end

  def handle_ice_message({:ice_payload, stream_id, component_id, payload}, _ctx, state) do
    %State{
      ice: ice,
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_ctx, handshake_state, _handshake_data} = Map.get(handshakes, component_id)

    if handshake_state != :finished do
      case handshake_module.recv_from_peer(handshake_ctx, payload) do
        {:ok, packets} ->
          ExLibnice.send_payload(ice, stream_id, component_id, packets)
          {:ok, state}

        {:finished_with_packets, handshake_data, packets} ->
          ExLibnice.send_payload(ice, stream_id, component_id, packets)

          handshakes =
            Map.put(handshakes, component_id, {handshake_ctx, :finished, handshake_data})

          new_state = %State{state | handshakes: handshakes}

          if MapSet.member?(state.connections, component_id) do
            {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
          else
            {:ok, new_state}
          end

        {:finished, handshake_data} ->
          handshakes =
            Map.put(handshakes, component_id, {handshake_ctx, :finished, handshake_data})

          new_state = %State{state | handshakes: handshakes}

          if MapSet.member?(state.connections, component_id) do
            {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
          else
            {:ok, new_state}
          end
      end
    else
      {:ok, state}
    end
  end

  def handle_ice_message(
        {:component_state_ready, stream_id, component_id},
        _ctx,
        %State{ice: ice} = state
      ) do
    Membrane.Logger.debug("Component #{component_id} READY")

    %State{
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {handshake_ctx, handshake_state, handshake_data} = Map.get(handshakes, component_id)

    new_connections = MapSet.put(state.connections, component_id)
    new_state = %State{state | connections: new_connections}

    if handshake_state == :finished do
      {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
    else
      case handshake_module.connection_ready(handshake_ctx) do
        :ok ->
          {:ok, new_state}

        {:ok, packets} ->
          ExLibnice.send_payload(ice, stream_id, component_id, packets)
          {:ok, new_state}

        {:finished_with_packets, handshake_data, packets} ->
          ExLibnice.send_payload(ice, stream_id, component_id, packets)

          handshakes =
            Map.put(handshakes, component_id, {handshake_ctx, :finished, handshake_data})

          new_state = %State{new_state | handshakes: handshakes}
          {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}

        {:finished, handshake_data} ->
          handshakes =
            Map.put(handshakes, component_id, {handshake_ctx, :finished, handshake_data})

          new_state = %State{new_state | handshakes: handshakes}
          {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
      end
    end
  end

  def handle_ice_message(msg, _ctx, state) do
    Membrane.Logger.warn("Unknown message #{inspect(msg)}")

    {:ok, state}
  end
end
