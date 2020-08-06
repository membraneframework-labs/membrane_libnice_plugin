module Membrane.ICE.Native

interface CNode

state_type "State"

spec init() :: {:ok :: label, state}

spec add_stream(state, n_components :: unsigned) :: {:ok :: label, stream :: unsigned}
       | {:error :: label, :failed_to_add_stream :: label}
       | {:error :: label, :failed_to_attach_recv :: label}

spec remove_stream(state, stream_id :: unsigned) :: {:ok :: label}

spec gather_candidates(state, stream_id :: unsigned) :: {:ok :: label, state}
       | {:error :: label, :invalid_stream_or_allocation :: label}

spec get_local_credentials(state, stream_id :: unsigned) :: {:ok :: label, credentials :: string}
       | {:error :: label, :failed_to_get_credentials :: label}

spec set_remote_credentials(state, credentials :: string, stream_id :: unsigned) :: {:ok :: label, state}
       | {:error :: label, :failed_to_set_credentials :: label}

spec set_remote_candidates(state, candidates :: string, stream_id :: unsigned, component_id :: unsigned) ::
       {:ok :: label, state}
       | {:error :: label, :failed_to_parse_sdp_string :: label}
       | {:error :: label, :failed_to_set :: label}

sends {:new_candidate_full :: label, candidate :: string}
sends {:candidate_gathering_done :: label}
sends {:new_selected_pair :: label, stream_id :: unsigned, component_id :: unsigned, lfoundation :: string, rfoundation :: string}
