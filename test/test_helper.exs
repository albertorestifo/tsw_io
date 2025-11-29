Mimic.copy(Req, type_check: true)
Mimic.copy(TswIo.Train.Identifier)
Mimic.copy(TswIo.Simulator.Client)
Mimic.copy(TswIo.Simulator)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TswIo.Repo, :manual)
