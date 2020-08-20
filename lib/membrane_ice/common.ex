defmodule Membrane.ICE.Common do
  require Unifex.CNode
  require Membrane.Logger

  def handle_ice_message({:add_stream, n_components}, _context, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :add_stream, [n_components]) do
      {:ok, stream_id} -> {{:ok, notify: {:stream_id, stream_id}}, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:get_local_credentials, stream_id}, _context, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :get_local_credentials, [stream_id]) do
      {:ok, credentials} -> {{:ok, notify: {:local_credentials, credentials}}, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_credentials, credentials, stream_id},
        _context,
        %{cnode: cnode} = state
      ) do
    case Unifex.CNode.call(cnode, :set_remote_credentials, [credentials, stream_id]) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:gather_candidates, stream_id}, _context, %{cnode: cnode} = state) do
    case Unifex.CNode.call(cnode, :gather_candidates, [stream_id]) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message(
        {:set_remote_candidate, candidates, stream_id, component_id},
        _context,
        %{cnode: cnode} = state
      ) do
    case Unifex.CNode.call(cnode, :set_remote_candidate, [candidates, stream_id, component_id]) do
      :ok -> {:ok, state}
      {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
    end
  end

  def handle_ice_message({:new_candidate_full, _ip} = msg, _context, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: msg}, state}
  end

  def handle_ice_message({:candidate_gathering_done} = msg, _context, state) do
    Membrane.Logger.debug("#{inspect(msg)}")
    {{:ok, notify: :gathering_done}, state}
  end
end
