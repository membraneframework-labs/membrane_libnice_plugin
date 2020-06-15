module Membrane.ICE.Agent.Native

spec create(
  # Following arguments map there two enums, with their prefixes stripped and lowercased.
  # NICE_COMPATIBILITY_DRAFT19 and *_LAST are not supported as they're obsolete in libnice.
  # https://libnice.freedesktop.org/libnice/NiceAgent.html#NiceCompatibility
  # https://libnice.freedesktop.org/libnice/NiceAgent.html#NiceAgentOption

  compatibility :: atom,
  options :: [atom]
) :: state

spec destroy(state) :: :ok

spec add_stream(state, n_components :: unsigned) ::
  {:ok :: label, stream_id :: unsigned} | {:error :: label, :failed_to_add :: label}

spec remove_stream(state, stream_id :: unsigned) :: (:ok :: label)

spec set_port_range(
  state,
  stream_id :: unsigned,
  component_id :: unsigned,
  min_port :: unsigned,
  max_port :: unsigned
) :: (:ok :: label)

spec gather_candidates(state, stream_id :: unsigned) ::
  (:ok :: label) | {:error :: label, :invalid_stream_or_interface :: label}
