# WAR STATE — DEVELOPMENT ROADMAP

## v0.4 delivered in source
- [x] Static six-plot map + large central island
- [x] Real Terrain water initialization before players join
- [x] Invisible boundaries
- [x] Central island vegetation, rocks and dirt paths
- [x] Bridges and plot exits
- [x] CIVILIAN / MILITARY / RESEARCH build menu
- [x] Treasury / economy cycles / building costs
- [x] Water and power service coverage
- [x] Population and workers
- [x] Coal / iron / oil / refinery / steel / warehouse chain
- [x] Civilian road traffic and simple procedural cars
- [x] Rail tracks / stations / freight trains
- [x] Stats panel + city-map data
- [x] Four-variant compact procedural models for current buildings
- [x] Server-side ownership and placement validation

## Next verification gate
- [ ] Build the place with real Rojo 7.7.0
- [ ] Run the generated place in Roblox Studio
- [ ] Run `RuntimeSelfTest` and fix any Studio-only issues
- [ ] Play through country creation, plot claiming, building, roads, utilities, economy, traffic, railway and stats

## Later
- [ ] DataStore session locking / offline construction progress
- [ ] Verified Roblox flag image assets
- [ ] Larger technology research tree
- [ ] Military vehicles leaving plots and using the central island battle area
- [ ] Unlock/monetize save slots 2 and 3

## Engineering rules
- Server authority for permanent state.
- Configurable gameplay in JSON.
- No heavy server Heartbeat/RenderStepped simulation loops.
- Real Rojo 7.7.0 is the only authoritative place build.
- Update this document and `PROJECT.md` whenever a new phase is actually implemented.
