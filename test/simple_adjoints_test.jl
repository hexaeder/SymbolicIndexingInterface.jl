using SymbolicIndexingInterface
using Zygote

sys = SymbolCache([:x, :y, :z], [:a, :b, :c], :t)
pstate = ProblemState(; u = rand(3), p = rand(3), t = rand())

getter = getu(sys, :x)
@test Zygote.gradient(getter, pstate)[1].u == [1.0, 0.0, 0.0]

getter = getu(sys, [:x, :z])
@test Zygote.gradient(sum ∘ getter, pstate)[1].u == [1.0, 0.0, 1.0]

getter = getu(sys, :a)
@test Zygote.gradient(getter, pstate)[1].p == [1.0, 0.0, 0.0]

getter = getu(sys, [:a, :c])
@test Zygote.gradient(sum ∘ getter, pstate)[1].p == [1.0, 0.0, 1.0]
