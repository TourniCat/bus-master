# PMM Reference Notes

Private Military Manager: Tactical Auto Battler is being studied as a reference for mechanics and implementation structure.

These notes describe concepts observed in the installed game files. They are not instructions to copy source code or assets.

## 1. Areas worth studying

The highest-value reference areas identified so far are:

1. combat AI
2. automatic combat camera
3. mission-map representation
4. lightweight pre-mission planning
5. equipment / loadout presentation
6. briefing and mission-flow UI

The PMM relationship system is less useful for this project because this game uses a fixed cast and needs deeper pair relationships.

## 2. Combat AI

PMM exposes a substantial simulation layer with separate decision areas for:

- visibility / awareness
- knowledge transfer
- target evaluation
- cover selection
- hiding / exploration
- route navigation
- fire control
- reload decisions
- grenade decisions
- healing
- door waiting / entry / breaching
- risk evaluation

Important design lesson:

> Build combat as a collection of understandable tactical decisions rather than one monolithic AI behavior.

For this project, PMM should be treated as evidence of which questions a competent tactical agent must answer, while our implementation remains independent.

## 3. Planning UI

PMM's planning layer is closer to behavioral policy than waypoint scripting.

Observed policy concepts include variants of:

- fire policy
- throwable permission / usage
- healing threshold
- breaching options
- risk-direction behavior
- door-entry behavior

This aligns with the desired design.

However, our version should likely be **simpler** because the game has only three persistent protagonists and should keep preparation fast.

## 4. Camera

PMM has strong reference value here.

Observed camera concepts include:

- automatic and manual control modes
- non-combat / encounter / cinematic states
- automatic framing based on relevant units
- combat framing that includes allies, enemies and aim targets
- inclusion of live throwables in framing
- automatic zoom based on the bounding area of relevant action
- smooth state transitions
- temporary manual override before returning to automatic direction
- event-driven camera movement for mission beats

Design lesson:

> In an auto battler, the camera is effectively the combat director.

Our camera should prioritize readability and spectacle without requiring constant player input.

## 5. Map representation

PMM separates simulation geometry from rendered level presentation.

Observed concepts include:

- world extents
- spawn areas
- obstacles
- polygons
- doors
- mission segments
- route/pathfinding data
- triggers / objectives
- runtime obstacle spawning
- authored Unreal levels used with simulation data

This suggests a useful production model:

> handcrafted level shell + structured tactical metadata + limited procedural variation

That is likely more practical for a small project than fully procedural 3D level generation.

## 6. Mission flow / UI

Observed UI/resource structure supports a flow roughly equivalent to:

- briefing
- squad / character preparation
- loadout
- planning
- simulation
- result / out-of-combat flow

Our version removes large-roster/company management and keeps only the parts needed by the fixed trio.

## 7. Relationship system

PMM appears to use relationship-like values mainly as character/event state rather than a deep pairwise three-dimensional social simulation.

For this project, do not inherit that limitation.

Because there are only three protagonists, explicitly model the three pair relationships and write authored events around them.

## 8. Legal / implementation boundary

Use PMM for:

- behavioral analysis
- UX-flow study
- system decomposition
- parameter-category inspiration
- identifying tactical AI problems that need solutions

Do not import or redistribute:

- PMM JavaScript source
- Unreal assets
- art
- audio
- localization
- dialogue
- maps
- proprietary names
- UI graphics
- exact authored data

Our implementation should be independently written.
