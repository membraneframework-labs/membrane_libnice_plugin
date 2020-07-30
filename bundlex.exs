defmodule Membrane.ICE.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  defp natives(_platform) do
    [
      native: [
        sources: ["native.c", "_generated/cnode/native.c"],
        deps: [unifex: :unifex],
        pkg_configs: ["nice"],
        libs: ["pthread"],
        interface: :cnode
      ]
    ]
  end
end
