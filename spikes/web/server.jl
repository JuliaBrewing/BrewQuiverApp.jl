# THROWAWAY spike: HTTP.jl + WebSocket + Cytoscape.js. The "session" here is a minimal
# stand-in for BrewQuiverUICore (undo stack of closures, transactions for drags).
t0 = time()
using HTTP, JSON, Unitful, UnitfulBrewing, BrewingFormulas, BrewQuiver
src = read(joinpath(@__DIR__, "..", "..", "..", "BrewQuiver.jl", "examples", "fullers_partigyle.jl"), String)
include_string(Main, src[1:findfirst("res = brew(q)", src).start-1])
const RES = Ref(brew(q))
const UNDO = Any[]; const REDO = Any[]; const TX = Ref{Any}(nothing)
println("server ready-to-serve after ", round(time()-t0, digits=1), " s"); flush(stdout)

fmt(x) = x === nothing ? nothing : round(ustrip(x), digits = 3)
safe(f, c) = try fmt(f(c)) catch; nothing end
function summary(n)
    c = RES[][n]
    (id = String(n), vessel = vessel(q, n) === nothing ? nothing : String(vessel(q, n)),
     volume = safe(x -> uconvert(u"L", volume(x)), c), gravity = safe(gravity, c),
     abv = safe(abv, c), ibu = safe(ibu, c), srm = safe(srm, c),
     position = get(nodeview(q, n), "position", nothing))
end
graph() = (type = "graph", nodes = [summary(n) for n in nodes(q)],
           edges = [(source = String(s), target = String(d), label = string(nameof(typeof(a))), i = i)
                    for (i, (s, d, a)) in enumerate(arrows(q))])

function rebrew_from(n)
    t = @elapsed rebrew!(RES[], q, n)
    changed = [n; descendants(q, n)]
    (type = "update", ms = 1000t, changed = [summary(m) for m in unique(changed) if haskey(q, m)])
end
function push_undo(desc, f)  # f undoes
    if TX[] === nothing; push!(UNDO, (desc, [f])); else push!(TX[][2], f); end
    empty!(REDO)
end

function handle(msg)
    c = msg["cmd"]
    if c == "begin";  TX[] = (msg["desc"], Any[]); return (type = "ack",)
    elseif c == "commit"; tx = TX[]; TX[] = nothing
        isempty(tx[2]) || push!(UNDO, (tx[1], reverse(tx[2]))); return history()
    elseif c == "move"   # layout-only: no rebrew
        n = Symbol(msg["node"]); v = nodeview(q, n); old = get(v, "position", nothing)
        v["position"] = [msg["x"], msg["y"]]
        push_undo("Move $n", () -> (old === nothing ? delete!(v, "position") : (v["position"] = old)))
        return (type = "ack",)
    elseif c == "scale"
        n = Symbol(msg["node"]); old = q[n].initial
        q[n] = msg["factor"] * old
        push_undo("Scale $n", () -> (q[n] = old; rebrew!(RES[], q, n)))
        return rebrew_from(n)
    elseif c == "connect"
        s, d = Symbol(msg["source"]), Symbol(msg["target"])
        try connect!(q, s => d) catch e; return (type = "error", message = sprint(showerror, e)); end
        push_undo("Connect $s → $d", () -> (disconnect!(q, s => d); rebrew!(RES[], q, s)))
        r = rebrew_from(s); return (; r..., graph = graph())
    elseif c == "undo"
        isempty(UNDO) && return (type = "ack",)
        desc, fs = pop!(UNDO); foreach(f -> f(), fs); push!(REDO, desc)
        return (type = "reload", graph = graph(), history = [d for (d, _) in UNDO])
    end
end
history() = (type = "history", undo = [d for (d, _) in UNDO])

const DIR = @__DIR__
HTTP.listen("127.0.0.1", 8765) do http
    if HTTP.WebSockets.isupgrade(http.message)
        HTTP.WebSockets.upgrade(http) do ws
            HTTP.WebSockets.send(ws, JSON.json(graph()))
            for raw in ws
                msg = JSON.parse(raw)
                reply = handle(msg)
                HTTP.WebSockets.send(ws, JSON.json((; reply..., seq = get(msg, "seq", 0))))
            end
        end
    else
        path = http.message.target == "/" ? "index.html" : lstrip(http.message.target, '/')
        f = joinpath(DIR, path)
        HTTP.setstatus(http, isfile(f) ? 200 : 404)
        HTTP.setheader(http, "Content-Type" => endswith(f, ".js") ? "text/javascript" : "text/html")
        HTTP.startwrite(http); isfile(f) && write(http, read(f))
    end
end
