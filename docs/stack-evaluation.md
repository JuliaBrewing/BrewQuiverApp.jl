# Stack evaluation for BrewQuiverApp

Status: proposal, awaiting a decision. No app code yet; the throwaway spikes that back the
numbers below are in [`spikes/`](../spikes).

## State of the dependencies (19 Nov 2026)

- **BrewQuiver.jl** (0.0.12, main): everything the app needs from the engine is there,
  including `nodeview`, JGF files with computed values, `timeline`, `solve!`.
- **BrewQuiverUICore.jl is empty** (README only), and BrewQuiverTerm.jl has no commits. The
  session, commands, history, view data and layout do not exist yet. The plan below starts
  with work that does not need them and puts every edit behind the core; the spikes used a
  20-line stand-in that will not go into the app.

## Measurements

On this container (4 cores, no GPU), with the parti-gyle of
`examples/fullers_partigyle.jl` (45 nodes, 50 arrows):

| | |
|---|---|
| `brew(q)`, warm | 0.5 ms |
| `rebrew!` from `:goldings` (23 nodes downstream), warm | 0.2–0.6 ms |
| `timeline(q)`, warm | 150 ms |
| first `brew` / `timeline` / `writejson` in a fresh process | 3.8 s / 3.7 s / 7.5 s |

**Rebrewing never limits live updates.** What limits them is first-call compilation (about
20 s for brew, timeline and save in a fresh process) and rendering. `timeline` at 150 ms is
fine on commit but too slow per drag frame.

| | Web (HTTP.jl + WS + Cytoscape.js/ELK) | Makie (GraphMakie) |
|---|---|---|
| install (fresh depot) | ≈2 min (BrewQuiver + HTTP + JSON) | 6.5 min more, 283 packages |
| package load | HTTP/JSON: negligible | GLMakie 3.5 s, CairoMakie 3.5 s |
| ready to draw | server up in 9.7 s; page + ELK layout in 0.7 s | first figure 9 s; first frame 4 s (Cairo) to 22 s (GL†) |
| edit → rebrew → redraw, warm | 6 ms round trip (median) | 66 ms GL†, 130 ms Cairo |
| drag frame | 14 ms per `move` message (queued, 30 frames) | local, but no server-side cost either |
| DAG layout | ELK layered, with vessels as compound groups: good (see `spike-web.png`) | Spring: unusable (`spike-makie.png`); LayeredLayouts.jl 1.8 s warm / 19 s first, no groups |

† Software OpenGL (Mesa under Xvfb); GLMakie cannot open a headless context here, and its
precompile workload failed for the same reason. On a desktop with a GPU it would be much
faster.

## Criteria

**Interactive graph editing.** Web: Cytoscape.js has node drag, box selection, zoom/pan and
compound nodes built in. Edge creation by dragging from a handle comes from
cytoscape-edgehandles, and context menus from cytoscape-cxtmenu. In the spike, a real
mouse drag sent `begin`/`move`×30/`commit`, and an arrow was created by `connect!` (a cycle
was refused with the engine's message). Makie: GraphMakie has `NodeDragHandler` and
hover/click handlers. Edge creation, context menus, selection rectangles and edge-label
hit-testing would all have to be written on top of `Makie.Events`.

**DAG layout.** The core is to own the layout (positions in `nodeview`). The web stack
draws those positions with Cytoscape's `preset` layout. ELK, in the browser, is a good
reference for what the core's layered layout should achieve: layers, few crossings, and
vessels as groups. Julia has no comparable layered layout: NetworkLayout has none, and
LayeredLayouts.jl solves a MILP (JuMP + HiGHS) and is too slow to run on each edit. If the
core's layout turns out weaker than ELK, ELK could run on demand in the app ("Tidy up") and
write positions back as one undoable layout command. That is a decision for you, since it
puts layout code outside the core.

**Forms with units.** Web: HTML inputs with a unit select per field. The text goes to
Julia, which parses it with Unitful/UnitfulBrewing and validates it through the core's
command, so units are never handled in JS. Makie: `Textbox` and `Menu` exist but are
basic: no tab order, weak focus handling, no layout for long forms.

**Live updates.** Both are fast warm. Web updates are a JSON diff of the changed nodes
(the core's changed set), applied with `ele.data(...)`. In Makie, every observable you
touch re-renders its plot.

**Undo/redo and transactions.** Web: the events map one to one. Cytoscape's
`grab`/`drag`/`free` become `begin`/`move`/`commit`, a form field's `change`/blur is one
mergeable command, Escape during a drag is `abort`, and `beforeunload` plus the core's saved
marker gives the unsaved-changes prompt. Ctrl+Z / Ctrl+Shift+Z and the menus send
`undo`/`redo`, and the history panel shows the core's step descriptions. In the spike, a
30-frame drag became exactly one undo step. Makie: `NodeDragHandler` gives drag start and
end too, but form commit and blur and the window-close prompt (GLFW) need custom code.

**Timeline/Gantt.** Easy either way: in Makie with `barplot`/`poly` on a time axis, on the
web with a few dozen SVG rects (or vis-timeline). It is driven by `timeline(q)`, on commit
only.

**Startup and precompile.** Both need a PrecompileTools workload, in the app and ideally in
BrewQuiver (see the engine proposals below). Makie adds ≈4 s of load and a long first
frame, on top of the engine's ≈20 s of first-call compilation, which affects both stacks.
The web front end itself is static JS that loads in under a second.

**Deployment.**
- *Desktop*: Web: `julia -m BrewQuiverApp` opens the default browser, or Chromium/Edge
  with `--app=` for a window without browser chrome. A Tauri/Electron shell is optional
  later. Makie: a native GLFW window, which needs OpenGL; it fails on headless and remote
  machines and on some VMs, as here.
- *Browser*: Web: native, local or hosted (several sessions on one Julia server).
  Makie: WGLMakie + Bonito, with the same widget limits as above.
- *Without a local Julia*: Web: a static read-only viewer of `.quiver.json` files works
  with no Julia at all, because `writejson(...; results)` stores the computed values.
  Editing needs Julia, either a hosted server or later a PackageCompiler bundle.
  Makie: no.

**Maturity and maintenance.** Makie is very active and well maintained (MakieOrg), but
GraphMakie is a small package, and graph *editing* is not its focus. Cytoscape.js
(2015–, MIT, very widely used) and elkjs (Eclipse) are mature. edgehandles is stable but
old: version 4 needs the lodash globals, which the spike had to provide. With the JS
vendored and no npm/bundler build, the JS side stays small: one page, a few hundred lines.
The cost is a second language and a protocol to maintain. Makie also clashes with
BrewQuiver's exports (`connect!`, `arrows`, …), so every name needs qualifying.

**Testability.** Web: the Julia side (view data → JSON, protocol → core commands) can be
tested as pure functions with `Test`, with no browser. End-to-end tests drive the real page
with Playwright (Chromium is preinstalled here and in CI images), as `drive.js` does.
Makie: logic in observables is testable, but interaction tests mean synthesizing
`Makie.Events`, and CI needs Xvfb + Mesa for GLMakie.

## Other options considered

- **Bonito.jl as the web transport** (instead of plain HTTP.jl + WebSockets): it gives
  observable sync and serves JS assets. That is convenient, but it hides the protocol, which
  I want explicit: messages are the core's commands, recorded and tested.
- **Genie/Stipple**: a full MVC framework with a Vue component model. It is heavier and its
  reactivity duplicates the core's session, while the graph canvas would still be
  Cytoscape.
- **Native GUI** (Gtk4.jl, Mousetrap.jl, QML.jl): good forms and menus, but no graph-editor
  widget, so the canvas would be hand-drawn on Cairo. More work than Makie for the graph.
- **React Flow** instead of Cytoscape: very good editing UX, but it needs React and a
  bundler (npm build). Cytoscape works from plain `<script>` tags.

## Recommendation

**The web stack:** a small HTTP.jl + WebSockets server in Julia, and a vendored-JS page
(Cytoscape.js + cytoscape-edgehandles + cytoscape-cxtmenu, elkjs optional, plain SVG for
the timeline), with no JS build step. JSON is the exchange format: JGF documents for files,
and the core's commands, serialized, as the edit protocol.

It wins on the editor itself: editing, layout quality, forms, the undo mapping, deployment
and testability. Makie remains the better choice for plots and static figures; an optional
extension could export Makie figures (timeline, provenance), but it should not be the editor.

## What the app will need from BrewQuiverUICore

Small additions, to be proposed as separate PRs once its API exists:

1. Commands that convert to and from JSON (`Dict`), so the protocol *is* the command set.
   Unknown or invalid commands return an error and leave the session unchanged. The spike
   showed that a bad edit (scaling a lot below what its transfers take) throws from
   `rebrew!`, so the core must roll back.
2. Transactions `begin`/`commit`/`abort` usable across messages (a drag spans many).
3. View data as plain `Dict`s/NamedTuples with formatted strings *and* numbers (for sorting
   and colors).
4. The changed set after each step, including after undo/redo.
5. A layout command (positions in `nodeview`) that is undoable without rebrewing.

## Engine-level proposals (BrewQuiver.jl, separate PRs, no UI code)

- A `PrecompileTools` workload (build a small quiver, `brew`, `rebrew!`, `timeline`,
  `writejson`/`readjson`) to remove most of the ≈20 s first-call delay. This helps the
  REPL, the terminal UI and the app alike.

## Milestones

Each is one PR. ⏳ marks a dependency on the core.

0. **Skeleton**: Project.toml with `[sources]` (BrewQuiver, siblings, BrewQuiverUICore),
   HTTP server, vendored JS, CI running Julia tests and one Playwright test.
1. **Viewer**: load a `.quiver.json` and show the graph (positions from the core's layout ⏳,
   or ELK until it lands), vessel groups and colors, arrow labels by process, and a side
   panel with node results (volume, gravity, ABV, IBU, SRM swatch, mash pH). Read-only.
2. **Session and protocol** ⏳: connect to the core's session. Edits as commands, changed
   nodes highlighted, undo/redo with Ctrl+Z / Ctrl+Shift+Z, menus with step descriptions,
   a history panel.
3. **Graph editing**: drag (transactions with abort), create and delete arrows and nodes,
   context menus, vessel assignment.
4. **Forms**: node contents and arrow parameters, with units, validation and merged edits.
5. **Files**: open, save, save as, BeerJSON import and export, and the unsaved-changes
   prompt (saved marker).
6. **Timeline**: a Gantt chart per vessel, overlaps flagged, linked selection with the graph.
7. **Targets and solve**: a targets/vary editor, `solve!` as one undoable step, and the
   solution report.
8. **Packaging**: `julia -m BrewQuiverApp`, an app-mode browser window, a static read-only
   viewer, and a precompile workload.
