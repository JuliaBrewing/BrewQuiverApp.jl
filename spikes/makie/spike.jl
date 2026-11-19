# THROWAWAY Makie spike: load times, GraphMakie layered layout, drag handler, observables.
backend = get(ENV, "BACKEND", "GLMakie")
t0 = time(); @eval using $(Symbol(backend)); tl = time() - t0
t0 = time(); using GraphMakie, NetworkLayout, Graphs; tg = time() - t0
println("load $backend ", round(tl, digits=1), " s; GraphMakie+NetworkLayout ", round(tg, digits=1), " s")
using BrewQuiver, Unitful, UnitfulBrewing, BrewingFormulas
using BrewQuiver: connect!, arrows, nodes, Vessel
exsrc = read(joinpath(@__DIR__, "..", "..", "..", "BrewQuiver.jl", "examples", "fullers_partigyle.jl"), String)
include_string(Main, exsrc[1:findfirst("res = brew(q)", exsrc).start-1])
res = brew(q)
labels = nodes(q); idx = Dict(l => i for (i, l) in enumerate(labels))
g = SimpleDiGraph(length(labels))
elabels = String[]
for (s, d) in unique([(s, d) for (s, d, _) in arrows(q)])
    add_edge!(g, idx[s], idx[d])
end
for e in edges(g)   # edge label order must follow Graphs' edge order
    push!(elabels, join(string.(nameof.(typeof.(q[labels[src(e)] => labels[dst(e)]]))), ","))
end
srmcol(c) = (s = try ustrip(srm(c)) catch; 0.0 end; t = min(s, 40) / 40; Makie.RGBf(0.98 - 0.5t, 0.9 - 0.8t, 0.47 - 0.43t))
colors = Observable([srmcol(res[l]) for l in labels])
t0 = time()
fig = Figure(size = (1400, 800))
ax = Axis(fig[1, 1]); hidedecorations!(ax)
lay = Spring()   # NetworkLayout has no layered (Sugiyama) layout in its release; Buchheim is trees only
p = graphplot!(ax, g; layout = lay, nlabels = String.(labels), node_color = colors,
               elabels = elabels, elabels_fontsize = 7, nlabels_fontsize = 9, arrow_shift = :end)
deregister_interaction!(ax, :rectanglezoom)
dragged = Ref(0)
function drag_cb(state, idx, event, axis)
    p[:node_pos][][idx] = event.data; p[:node_pos][] = p[:node_pos][]
    dragged[] += 1   # state: true at start, false at end -> begin/commit of a transaction
end
register_interaction!(ax, :ndrag, NodeDragHandler(drag_cb))
sl = Slider(fig[2, 1], range = 0.5:0.01:1.5, startvalue = 1.0)
base = q[:goldings].initial
on(sl.value) do f
    q[:goldings] = f * base
    t = @elapsed rebrew!(res, q, :goldings)
    colors[] = [srmcol(res[l]) for l in labels]
    println("rebrew! + observable update ", round(1000t, digits=2), " ms")
end
println("build figure ", round(time() - t0, digits=1), " s")
t0 = time(); save("makie_$backend.png", fig); println("first save ", round(time() - t0, digits=1), " s")
t0 = time(); set_close_to!(sl, 1.2); println("slider update ", round(1000(time() - t0), digits=1), " ms")
ts = Float64[]
for f in 1.0:0.02:1.18
    local t0 = time(); set_close_to!(sl, f); backend == "CairoMakie" ? save("tmp.png", fig) : (backend == "GLMakie" && Makie.colorbuffer(fig)); push!(ts, 1000(time() - t0))
end
sort!(ts); println("warm edit -> rebrew -> re-render ms median ", round(ts[end ÷ 2], digits=1))
