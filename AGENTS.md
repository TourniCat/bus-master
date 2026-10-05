# Project Working Rules

## Product direction

This repository contains a character-focused tactical auto battler built around three fixed protagonists.

Read these before making design or implementation changes:

- `docs/DESIGN_FOUNDATION.md`
- `docs/DECISIONS.md`
- `docs/PMM_REFERENCE.md`
- `docs/PLANNING.md`

## Non-negotiable current principles

- Three persistent protagonists.
- All three normally deploy.
- No large mercenary roster or company-management loop.
- Combat AI behaves professionally.
- Relationships do not cause irrational tactical decisions.
- Pre-mission planning is lightweight doctrine, not detailed waypoint scripting.
- Injury usually becomes downtime rather than forced roster substitution.

## PMM reference boundary

PMM files may be analyzed to understand behavior and system architecture.

Do not copy PMM source, assets, text, UI graphics, map content or other proprietary expression into this repository.

Reimplement mechanics independently.

## Design workflow

When a design decision becomes settled:

1. update `docs/DECISIONS.md`
2. update the relevant design document
3. remove contradictory stale notes

Do not silently treat brainstorming as a final requirement.
