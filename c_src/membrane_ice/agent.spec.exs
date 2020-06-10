module Membrane.ICE.Agent.Native

spec create() :: {:ok :: label, state} | {:error :: label, string}

spec destroy(state) :: :ok
