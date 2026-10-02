# WAR STATE - DEVELOPMENT_ROADMAP.md

> Future plan + phase log. What exists today is in PROJECT.md.

## v0.4 phases (branch `main`, each phase = green GitHub Actions with real Rojo 7.7.0)
- [x] **Phase 1 - Static map**: map in the place file, no runtime/PlayerAdded generation, big central island,
      x3 spacing, Terrain water at server start, invisible boundaries, trees/bushes/rocks/dirt paths, bridges, exits.
- [x] **Phase 2 - UI / Build Menu / Economy**: CIVILIAN / MILITARY / RESEARCH only, wide bottom menu, vertical categories,
      cards with lock state, population unlocks (no deadlock at 0), Treasury 0, cost / income / expense, 30 s cycles, HUD.
- [x] **Phase 3 - Resources / Industry**: Coal Mine, Iron Mine, Oil Well, Refinery, Steel Factory, Warehouse, chains.
- [x] **Phase 4 - Civilian traffic**: every 60 s ceil(houses/2) cars, House -> Shop/Gas Station/Office on real roads.
- [x] **Phase 5 - Railway**: Rail Track drag build, Railway Station, Freight Train, resource logistics.
- [x] **Phase 6 - City Stats**: sections + 2D city map with buildings, roads, water/power overlays and coverage radii.
- [ ] **Studio Play verification** of Phases 2-6 (needs Roblox Studio; RuntimeSelfTest + checklist in PROJECT.md).

## Later
- DataStore session locking (UpdateAsync with session id); offline construction / production progress
- Verified flag image assets (only real Roblox ids)
- Research tree (USSR / Russia, USA, Germany lines; no doctrine system)
- Military: vehicles leave plots through exits and fight on the central island
- Unlock slots 2 and 3

## Engineering rules
Server authority for all permanent state; config in JSON; no RenderStepped / Heartbeat loops on the server;
event-driven recomputes; real `rojo build` only; update PROJECT.md and this file after every phase.
