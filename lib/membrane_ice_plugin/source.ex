defmodule Membrane.ICE.Source do
  @moduledoc """
  Element that convey buffers to relevant pads.

  Multiple components are handled with dynamic pads. Receiving data on component with id
  `component_id` will cause in conveying this data on pad with id `component_id`.

  Other elements can be linked to the Sink in any moment but before playing pipeline. Playing your
  pipeline is possible only after linking all pads. E.g. if your stream has 2 components you have to
  link to the Source using two dynamic pads with ids 1 and 2 and after this you can play your
  pipeline.
  """

  use Membrane.Source

  alias Membrane.ICE.Common

  require Membrane.Logger

  def_options n_components: [
                type: :integer,
                default: 1,
                description: "Number of components specified in connector"
              ]

  def_output_pad :output,
    availability: :on_request,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(options) do
    %__MODULE__{
      n_components: n_components
    } = options

    {:ok, %{n_components => n_components}}
  end

  @impl true
  def handle_prepared_to_playing(ctx, state) do
    Common.handle_prepared_to_playing(ctx, state)
  end

  @impl true
  def handle_notification({:ice_payload, component_id, payload} = msg, _from, ctx, state) do
    actions = [buffer: {Pad.ref(:output, component_id), %Membrane.Buffer{payload: payload}}]
    {{:ok, actions}, state}
  end
end
