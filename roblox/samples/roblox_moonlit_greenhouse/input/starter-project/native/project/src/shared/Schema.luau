--!strict
return {
  ContractVersion = 1, Contract = "moonlit-greenhouse-v1", Prefix = "MG_",
  Cycles = 4, Beds = {"A","B","C"}, Phases = {-1,0,1},
  Targets = {
    [1] = {A={Water=2,Light=2,Phase=0},B={Water=1,Light=3,Phase=1},C={Water=3,Light=1,Phase=-1}},
    [2] = {A={Water=1,Light=3,Phase=1},B={Water=2,Light=1,Phase=-1},C={Water=2,Light=2,Phase=0}},
    [3] = {A={Water=3,Light=2,Phase=-1},B={Water=2,Light=2,Phase=0},C={Water=1,Light=3,Phase=1}},
    [4] = {A={Water=2,Light=1,Phase=0},B={Water=3,Light=2,Phase=1},C={Water=1,Light=2,Phase=-1}},
  },
  Initial = {Water=8, Energy=6, Cycle=1, Integrity=100, Faults=0, FinalStage="Locked"}
}
