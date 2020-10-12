# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Membrane.ICE.Common do
  @moduledoc false

  # Module containing common behaviour for Sink and Source modules.

  require Unifex.CNode
  require Membrane.Logger

  defmodule State do
    @moduledoc false

    @type handshake_state :: :in_progress | :finished | :disabled
    @type handshake_data :: term()
    @type component_id :: integer()

    @type t :: %__MODULE__{
            ice: pid(),
            controlling_mode: boolean(),
            stream_id: integer(),
            handshakes: %{component_id() => {pid, handshake_state, handshake_data}},
            handshake_module: Handshake.t(),
            connections: MapSet.t()
          }
    defstruct ice: nil,
              controlling_mode: false,
              stream_id: nil,
              handshakes: %{},
              handshake_module: Handshake.Default,
              connections: MapSet.new()
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
      handshakes: %{^component_id => {dtls_pid, _handshake_state, _handshake_data}} = handshakes,
      handshake_module: handshake_module
    } = state

    case handshake_module.recv_from_peer(dtls_pid, payload) do
      {:ok, packets} ->
        ExLibnice.send_payload(ice, stream_id, component_id, packets)
        {:ok, state}

      {:finished_with_packets, handshake_data, packets} ->
        ExLibnice.send_payload(ice, stream_id, component_id, packets)
        update_state_and_return(component_id, dtls_pid, handshake_data, handshakes, state)

      {:finished, handshake_data} ->
        update_state_and_return(component_id, dtls_pid, handshake_data, handshakes, state)
    end
  end

  def handle_ice_message(
        {:component_state_ready, stream_id, component_id},
        _ctx,
        %State{ice: ice, controlling_mode: controlling_mode} = state
      ) do
    Membrane.Logger.debug("Component #{component_id} READY")

    %State{
      handshakes: handshakes,
      handshake_module: handshake_module
    } = state

    {pid, handshake_state, handshake_data} = Map.get(handshakes, component_id)

    new_connections = MapSet.put(state.connections, component_id)
    new_state = %State{state | connections: new_connections}

    if handshake_state == :finished do
      {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
    else
      if controlling_mode do
        {:ok, packets} = handshake_module.connection_ready(pid)
        ExLibnice.send_payload(ice, stream_id, component_id, packets)
      end

      {:ok, new_state}
    end
  end

  def handle_ice_message(msg, _ctx, state) do
    Membrane.Logger.warn("Unknown message #{inspect(msg)}")

    {:ok, state}
  end

  defp update_state_and_return(component_id, dtls_pid, handshake_data, handshakes, state) do
    handshakes = Map.put(handshakes, component_id, {dtls_pid, :finished, handshake_data})
    new_state = %State{state | handshakes: handshakes}

    if MapSet.member?(state.connections, component_id) do
      {{:ok, notify: {:component_state_ready, component_id, handshake_data}}, new_state}
    else
      {:ok, new_state}
    end
  end
end
