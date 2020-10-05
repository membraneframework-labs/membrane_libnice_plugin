defmodule Membrane.ICE.Common do
  @moduledoc false

  # Module containing common behaviour for Sink and Source modules.

  require Unifex.CNode
  require Membrane.Logger

  def handle_ice_message({:add_stream, n_components}, ctx, state) do
    handle_ice_message({:add_stream, n_components, ""}, ctx, state)
  end

  def handle_ice_message({:add_stream, n_components, name}, _ctx, %{ice: ice} = state) do
    case ExLibnice.add_stream(ice, n_components, name) do
      {:ok, stream_id} ->
        {{:ok, notify: {:stream_id, stream_id}}, state}

      {:error, cause} ->
        {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:remove_stream, stream_id}, _ctx, %{ice: ice} = state) do
    :ok = ExLibnice.remove_stream(ice, stream_id)
    {:ok, state}
  end

  def handle_ice_message(:generate_local_sdp, _ctx, %{ice: ice} = state) do
    {:ok, local_sdp} = ExLibnice.generate_local_sdp(ice)

    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp

    Membrane.Logger.debug("local sdp: #{inspect(local_sdp)}")

    {{:ok, notify: {:local_sdp, local_sdp}}, state}
  end

  def handle_ice_message({:parse_remote_sdp, sdp}, _ctx, %{ice: ice} = state) do
    case ExLibnice.parse_remote_sdp(ice, sdp) do
      {:ok, added_cand_num} ->
        {{:ok, notify: {:parse_remote_sdp_ok, added_cand_num}}, state}

      {:error, cause} ->
        {{:error, cause}, state}
    end
  end

  def handle_ice_message({:get_local_credentials, stream_id}, _ctx, %{ice: ice} = state) do
    case ExLibnice.get_local_credentials(ice, stream_id) do
      {:ok, credentials} -> {{:ok, notify: {:local_credentials, credentials}}, state}
      {:error, cause} -> {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_credentials, credentials, stream_id},
        _ctx,
        %{ice: ice} = state
      ) do
    result = ExLibnice.set_remote_credentials(ice, credentials, stream_id)
    {result, state}
  end

  def handle_ice_message({:gather_candidates, stream_id}, _ctx, %{ice: ice} = state) do
    case ExLibnice.gather_candidates(ice, stream_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:peer_candidate_gathering_done, stream_id},
        _ctx,
        %{ice: ice} = state
      ) do
    case ExLibnice.peer_candidate_gathering_done(ice, stream_id) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_candidate, candidate, stream_id, component_id},
        _ctx,
        %{ice: ice} = state
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

    {{:ok, notify: msg}, state}
  end

  def handle_ice_message(
        {:new_selected_pair, _stream_id, _component_id, _lfoundation, _rfoundation} = msg,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("#{inspect(msg)}")

    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:component_state_failed, _stream_id, _component_id}, _ctx, state) do
    {:ok, state}
  end

  def handle_ice_message(msg, _ctx, state) do
    Membrane.Logger.warn("Unknown message #{inspect(msg)}")

    {:ok, state}
  end
end
