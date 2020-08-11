defmodule Membrane.Element.ICE.Common do
  defmacro __using__(_options) do
    quote location: :keep do
      require Unifex.CNode

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
      def handle_other({:add_stream, n_components}, _context, %{cnode: cnode} = state) do
        case Unifex.CNode.call(cnode, :add_stream, [n_components]) do
          {:ok, stream_id} -> {{:ok, notify: {:stream_id, stream_id}}, state}
          {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
        end
      end

      @impl true
      def handle_other({:get_local_credentials, stream_id}, _context, %{cnode: cnode} = state) do
        case Unifex.CNode.call(cnode, :get_local_credentials, [stream_id]) do
          {:ok, credentials} -> {{:ok, notify: {:local_credentials, credentials}}, state}
          {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
        end
      end

      @impl true
      def handle_other(
            {:set_remote_credentials, credentials, stream_id},
            _context,
            %{cnode: cnode} = state
          ) do
        case Unifex.CNode.call(cnode, :set_remote_credentials, [credentials, stream_id]) do
          :ok -> {:ok, state}
          {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
        end
      end

      @impl true
      def handle_other({:gather_candidates, stream_id}, _context, %{cnode: cnode} = state) do
        case Unifex.CNode.call(cnode, :gather_candidates, [stream_id]) do
          :ok -> {:ok, state}
          {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
        end
      end

      @impl true
      def handle_other(
            {:set_remote_candidate, candidates, stream_id, component_id},
            _context,
            %{cnode: cnode} = state
          ) do
        case Unifex.CNode.call(cnode, :set_remote_candidate, [candidates, stream_id, component_id]) do
          :ok -> {:ok, state}
          {:error, cause} -> {{:ok, notify: {:error, cause}}, state}
        end
      end

      @impl true
      def handle_other({:new_candidate_full, _ip} = candidate, _context, state) do
        {{:ok, notify: candidate}, state}
      end

      @impl true
      def handle_other({:candidate_gathering_done}, _context, state) do
        {{:ok, notify: :gathering_done}, state}
      end
    end
  end
end
