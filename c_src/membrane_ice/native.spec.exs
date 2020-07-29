module(Membrane.ICE.Native)

interface(CNode)

spec init() :: {:ok :: label}

spec start_gathering_candidates() :: {:ok :: label}

sends {:candidate :: label, candidate :: string}
sends {:gathering_done :: label}
