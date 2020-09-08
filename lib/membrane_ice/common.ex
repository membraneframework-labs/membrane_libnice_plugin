defmodule Membrane.ICE.Common do
  @moduledoc false

  # Module containing common behaviour for Sink and Source modules.

  require Unifex.CNode
  require Membrane.Logger

  def handle_ice_message({:add_stream, n_components}, ctx, state) do
    handle_ice_message({:add_stream, n_components, ""}, ctx, state)
  end

  def handle_ice_message({:add_stream, n_components, name}, _ctx, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :add_stream, [n_components, name]) do
      {:ok, stream_id} ->
        Membrane.Logger.debug("New stream_id: #{stream_id}")

        {{:ok, notify: {:stream_id, stream_id}}, state}

      {:error, cause} ->
        Membrane.Logger.warn("""
        Couldn't add stream with #{n_components} components and name "#{inspect(name)}":
        #{inspect(cause)}
        """)

        {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:remove_stream, stream_id}, _ctx, %{cnode: cnode} = state) do
    :ok = Unifex.CNode.call(cnode, :remove_stream, [stream_id])

    Membrane.Logger.debug("remove_stream #{stream_id}: ok")

    {:ok, state}
  end

  def handle_ice_message(:generate_local_sdp, _ctx, %{cnode: cnode} = state) do
    {:ok, local_sdp} = Unifex.CNode.call(cnode, :generate_local_sdp)

    # the version of the SDP protocol. RFC 4566 defines only v=0 - section 5.1
    local_sdp = "v=0\r\n" <> local_sdp

    Membrane.Logger.debug("local sdp: #{inspect(local_sdp)}")

    {{:ok, notify: {:local_sdp, local_sdp}}, state}
  end

  def handle_ice_message({:parse_remote_sdp, remote_sdp}, _ctx, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :parse_remote_sdp, [remote_sdp]) do
      {:ok, added_cand_num} ->
        Membrane.Logger.debug("parse_remote_sdp: ok; added #{added_cand_num} candidates")

        {{:ok, notify: {:parse_remote_sdp_ok, added_cand_num}}, state}

      {:error, cause} ->
        Membrane.Logger.warn("Couldn't parse remote sdp #{inspect(remote_sdp)}")

        {{:error, cause}, state}
    end
  end

  def handle_ice_message({:get_local_credentials, stream_id}, _ctx, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :get_local_credentials, [stream_id]) do
      {:ok, credentials} ->
        Membrane.Logger.debug("local credentials: #{credentials}")

        {{:ok, notify: {:local_credentials, credentials}}, state}

      {:error, cause} ->
        Membrane.Logger.error("get_local_credentials: #{inspect(cause)}")

        {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_credentials, credentials, stream_id},
        _ctx,
        %{cnode: cnode} = state
      ) do
    case Unifex.CNode.call(cnode, :set_remote_credentials, [credentials, stream_id]) do
      :ok ->
        Membrane.Logger.debug("set_remote_credentials: ok")

        {:ok, state}

      {:error, cause} ->
        Membrane.Logger.error("set_remote_credentials: #{inspect(cause)}")

        {{:error, cause}, state}
    end
  end

  def handle_ice_message({:gather_candidates, stream_id} = msg, _ctx, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :gather_candidates, [stream_id]) do
      :ok ->
        Membrane.Logger.debug("#{inspect(msg)}")

        {:ok, state}

      {:error, cause} ->
        Membrane.Logger.error("gather_candidates: #{inspect(msg)}")

        {{:error, cause}, state}
    end
  end

  def handle_ice_message(
        {:peer_candidate_gathering_done, stream_id},
        _ctx,
        %{cnode: cnode} = state
      ) do
    case Unifex.CNode.call(cnode, :peer_candidate_gathering_done, [stream_id]) do
      :ok ->
        Membrane.Logger.debug("peer_candidate_gathering_done: ok")

        {:ok, state}

      {:error, cause} ->
        Membrane.Logger.warn("peer_candidate_gathering_done: #{inspect(cause)}")

        {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_candidate, candidate, stream_id, component_id},
        _ctx,
        %{cnode: cnode} = state
      ) do
    case Unifex.CNode.call(cnode, :set_remote_candidate, [candidate, stream_id, component_id]) do
      :ok ->
        Membrane.Logger.debug("Set remote candidate: #{inspect(candidate)}")

        {:ok, state}

      {:error, cause} ->
        Membrane.Logger.warn("Couldn't set remote candidate: #{inspect(cause)}")

        {{:ok, notify: {:error, cause}}, state}
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

  def handle_ice_message({:component_state_failed, _stream_id, _component_id} = msg, _ctx, state) do
    Membrane.Logger.warn("#{inspect(msg)}")

    {:ok, state}
  end

  def handle_ice_message(msg, _ctx, state) do
    Membrane.Logger.warn("Unknown message #{inspect(msg)}")

    {:ok, state}
  end
end
