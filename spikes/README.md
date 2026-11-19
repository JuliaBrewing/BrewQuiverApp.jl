# Throwaway spikes (stack evaluation)

Not app code: they exist only to check the claims of
[`docs/stack-evaluation.md`](../docs/stack-evaluation.md), and will be deleted when the app starts.
Both load the parti-gyle of `BrewQuiver.jl/examples/fullers_partigyle.jl` (45 nodes, 50 arrows)
from a sibling checkout at `../BrewQuiver.jl`, and use a minimal stand-in for the editing session of
BrewQuiverUICore (still empty).

- `web/`: HTTP.jl + WebSockets server (`server.jl`) and a Cytoscape.js page (`index.html`) with
  the ELK layered layout, vessel groups, node drag (as a begin/move.../commit transaction) and
  edge creation (cytoscape-edgehandles). `drive.js` drives it with Playwright and prints the
  timings. The JS libraries are fetched from jsDelivr (cytoscape 3.30.2, elkjs 0.9.3,
  cytoscape-elk 2.2.0, cytoscape-edgehandles 4.0.1, lodash 4.17.21) into `web/`.
- `makie/`: GraphMakie with NetworkLayout, `NodeDragHandler`, a `Slider` driving `rebrew!`
  through an observable (`BACKEND=GLMakie|CairoMakie julia spike.jl`), and `layered.jl` timing
  LayeredLayouts.jl.

Run the web spike with `julia --project=<env with BrewQuiver, HTTP, JSON> spikes/web/server.jl`,
then `node spikes/web/drive.js` (or open http://127.0.0.1:8765).
