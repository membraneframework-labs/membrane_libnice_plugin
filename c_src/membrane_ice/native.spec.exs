module Membrane.ICE.Native

interface CNode

state_type "State"

spec init() :: {:ok :: label, state}

spec gather_candidates(state) :: {:ok :: label, state}

spec get_local_credentials(state) :: {:ok :: label, credentials :: string}
       | {:error :: label, :failed_to_get_credentials :: label}

spec set_remote_credentials(state, credentials :: string) :: {:ok :: label, state}
       | {:error :: label, :failed_to_set_credentials :: label}

spec set_remote_candidates(state, candidates :: string) :: {:ok :: label, state}
       | {:error :: label, :failed_to_parse_sdp_string :: label}
       | {:error :: label, :failed_to_set :: label}

sends {:new_candidate_full :: label, candidate :: string}
sends {:candidate_gathering_done :: label}
