defmodule Membrane.ICE.Common2 do
  @spec handle_prepared_to_playing(
          ctx :: PlaybackChange.t(),
          state :: State.t()
        ) ::
          Base.callback_return_t()
  def handle_prepared_to_playing(ctx, state) do
    unlinked_components =
      Enum.reject(1..state.n_components, &Map.has_key?(ctx.pads, Pad.ref(pads_type, &1)))

    if Enum.empty?(unlinked_components) do
      {:ok, state}
    else
      raise "Pads for components no. #{Enum.join(unlinked_components, ", ")} haven't been linked"
    end
  end
end
