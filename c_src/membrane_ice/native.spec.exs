module Membrane.ICE.Native

interface CNode

state_type "State"

spec init() :: {:ok :: label, state}

spec start_gathering_candidates(state) :: {:ok :: label, state}

sends {:candidate :: label, candidate :: string}
sends {:gathering_done :: label}
