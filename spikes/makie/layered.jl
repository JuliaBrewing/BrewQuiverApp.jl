using LayeredLayouts, Graphs, BrewQuiver, Unitful, UnitfulBrewing, BrewingFormulas
exsrc = read(joinpath(@__DIR__, "..", "..", "..", "BrewQuiver.jl", "examples", "fullers_partigyle.jl"), String)
include_string(Main, exsrc[1:findfirst("res = brew(q)", exsrc).start-1])
labels = nodes(q); idx = Dict(l => i for (i, l) in enumerate(labels))
g = SimpleDiGraph(length(labels)); for (s, d, _) in arrows(q); add_edge!(g, idx[s], idx[d]); end
t = @elapsed (xs, ys, paths) = solve_positions(Zarate(), g); println("LayeredLayouts Zarate first ", t)
t = @elapsed solve_positions(Zarate(), g); println("LayeredLayouts Zarate warm ", t)
