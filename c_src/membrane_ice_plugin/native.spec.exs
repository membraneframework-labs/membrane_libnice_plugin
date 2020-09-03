module Membrane.ICE.Native

interface CNode

state_type "State"

spec init(stun_servers :: [string], turn_servers :: [string], controlling_mode :: int) ::
       {:ok :: label, state}

spec add_stream(state, n_components :: unsigned, name :: string) :: {:ok :: label, stream_id :: unsigned}
       | {:error :: label, :failed_to_add_stream :: label}
       | {:error :: label, :invalid_stream_or_duplicate_name :: label}
       | {:error :: label, :failed_to_attach_recv :: label}

spec remove_stream(state, stream_id :: unsigned) :: {:ok :: label}

spec generate_local_sdp(state) :: {:ok :: label, local_sdp :: string}

spec parse_remote_sdp(state, remote_sdp :: string) :: {:ok :: label, added_cand_num :: unsigned}
       | {:error :: label, :failed_to_parse_sdp :: label}

spec get_local_credentials(state, stream_id :: unsigned) :: {:ok :: label, credentials :: string}
       | {:error :: label, :failed_to_get_credentials :: label}

spec set_remote_credentials(state, credentials :: string, stream_id :: unsigned) :: {:ok :: label, state}
       | {:error :: label, :failed_to_set_credentials :: label}

spec gather_candidates(state, stream_id :: unsigned) :: {:ok :: label, state}
       | {:error :: label, :invalid_stream_or_allocation :: label}

spec peer_candidate_gathering_done(state, stream_id :: unsigned) :: {:ok :: label, state}
       | {:error :: label, :stream_not_found :: label}

spec set_remote_candidate(state, candidate :: string, stream_id :: unsigned, component_id :: unsigned) ::
       {:ok :: label, state}
       | {:error :: label, :failed_to_parse_sdp_string :: label}
       | {:error :: label, :failed_to_set :: label}

spec send_payload(state, stream_id :: unsigned, component_id :: unsigned, data :: payload) :: {:ok :: label, state}
       | {:error :: label, :failed_to_send :: label}

sends {:new_candidate_full :: label, candidate :: string}
sends {:new_remote_candidate_full :: label, candidate :: string}
sends {:candidate_gathering_done :: label, stream_id :: unsigned}
sends {:new_selected_pair :: label, stream_id :: unsigned, component_id :: unsigned, lfoundation :: string, rfoundation :: string}
sends {:component_state_failed :: label, stream_id :: unsigned, component_id :: unsigned}
sends {:component_state_ready :: label, stream_id :: unsigned, component_id :: unsigned}
sends {:ice_payload :: label, stream_id :: unsigned, component_id :: unsigned, payload :: payload}

