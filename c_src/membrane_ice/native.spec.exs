module Membrane.ICE.Native

interface CNode

state_type "State"

spec init() :: {:ok :: label, state}

spec gather_candidates(state) :: {:ok :: label, state}

sends {:new_candidate_full :: label, candidate :: string}
sends {:candidate_gathering_done :: label}
