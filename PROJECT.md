# WAR STATE — PROJECT.md (v0.4)

**Version:** 0.4.0 WIP-ready source
**Build system:** Rojo 7.7.0
**Source of truth:** repository contents under `src/`

## Current state
The v0.4 source combines the Phase 1 static-map architecture with the v0.4 gameplay/UI systems.
The project is prepared for a real Rojo 7.7.0 build and Roblox Studio verification.

### Game flow
`MAIN MENU` -> `CREATE COUNTRY` -> `PLOT SELECTION` -> `GAME`

Country setup is: Name -> Continent -> Flag (195) -> Technology branch -> Review.
A player must explicitly choose one of the six free plots after creating/loading a country. The plot owner sign shows player name, flag and country name; the technology branch is not displayed on the sign.

## Implemented source systems
| Area | Status |
|---|---|
| 195 countries / 6 continents / flag fallback | Implemented |
| 3 save slots (1 free, 2 locked) | Implemented |
| Static world map and six plots | Implemented in source |
| Central island + decorations + bridges + exits | Implemented in source |
| Terrain water initialized once at server start | Implemented |
| Invisible map boundaries | Implemented |
| Plot ownership / server authority | Implemented |
| Small procedural building models | Implemented |
| Straight road drag placement | Implemented |
| CIVILIAN / MILITARY / RESEARCH build menu | Implemented |
| Construction bars | Implemented |
| Treasury / 30-second economy cycles | Implemented |
| Water and power coverage / shortage stages | Implemented |
| Population / workers | Implemented |
| Coal / iron / oil / refinery / steel / storage chain | Implemented |
| Civilian road traffic | Implemented |
| Rail track / stations / freight trains | Implemented |
| Stats + city-map data endpoint/UI | Implemented |
| Research buildings / research points | Implemented |

## Rules preserved from the design
- Starting Treasury = 0.
- Starting resources = 0.
- Starting population/housing/workers = 0.
- Basic first house is free so the zero-money/zero-population state is not a deadlock.
- Roads use one straight type.
- Permanent building labels are not attached to building models.
- Building placement, roads, demolition, construction and resources are revalidated by the server.
- No runtime map generation on PlayerAdded.

## Map
- Central island: 520 x 520.
- Six player islands are spaced well outside the central island and connect through one bridge/exit each.
- Static source files are in `src/Workspace/Map/`.
- `tools/gen_static_map.py` deterministically regenerates the eight map files.
- Terrain water is runtime-initialized once before players can join because terrain voxel water is not serialized by Rojo source files.

## Build / validation
### Offline structural validation
```text
python tools/gen_static_map.py --check
python -m unittest discover -s tests -t . -v
```

### Real build
Use **Rojo 7.7.0** with `default.project.json` to produce `build/WarState.rbxlx` and then run the release checks. The offline `tools/rojo_build.py` is only a structure mirror and must never be described as a real Rojo build.

## Studio verification
The source contains `RuntimeSelfTest` for Studio-side checks. Studio-only claims must be made only after a real Play test.
