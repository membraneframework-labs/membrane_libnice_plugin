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
        {:ok, stream_id} = Unifex.CNode.call(cnode, :add_stream, [n_components])
        {{:ok, notify: {:stream_id, stream_id}}, state}
      end

      @impl true
      def handle_other({:get_local_credentials, stream_id}, _context, %{cnode: cnode} = state) do
        {:ok, credentials} = Unifex.CNode.call(cnode, :get_local_credentials, [stream_id])
        {{:ok, notify: {:local_credentials, credentials}}, state}
      end

      @impl true
      def handle_other({:set_remote_credentials, credentials, stream_id}, _context, %{cnode: cnode} = state) do
        :ok = Unifex.CNode.call(cnode, :set_remote_credentials, [credentials, stream_id])
        {:ok, state}
      end

      @impl true
      def handle_other({:gather_candidates, stream_id}, _context, %{cnode: cnode} = state) do
        Unifex.CNode.call(cnode, :gather_candidates, [stream_id])
        {:ok, state}
      end

      @impl true
      def handle_other({:new_candidate_full, _ip} = candidate, _context, state) do
        {{:ok, notify: candidate}, state}
      end

      @impl true
      def handle_other({:candidate_gathering_done}, _context, state) do
        {{:ok, notify: :gathering_done}, state}
      end

      @impl true
      def handle_other({:set_remote_candidates, candidates, stream_id, component_id}, _context, %{cnode: cnode} = state) do
        Unifex.CNode.call(cnode, :set_remote_candidates, [candidates, stream_id, component_id])
        {:ok, state}
      end
    end
  end
end
