# Decision Log

This file records decisions already made so future planning does not repeatedly reopen settled questions without a reason.

## 2026-10-06 — Project reset

The retired `bus-master` repository is repurposed for a new tactical auto-battler project.

## Fixed cast instead of random mercenaries

Decision:

- Use authored, persistent protagonists.
- Do not use PMM-style disposable/random recruitment as the core character model.

Reason:

Character attachment is central to the new concept.

## Remove company-management layer

Decision:

- no PMC-company simulation
- no employee-management fantasy
- no large recruitment loop

Premise:

Three friends take armed jobs to make money.

## Three-character team

Decision:

- fixed cast of 3
- standard deployment of all 3

Earlier alternatives considered:

- 6 characters / 4 deploy
- 4 characters / 3 deploy

The fixed trio was chosen because it gives the strongest character identity and matches the desired small-team feel.

## Injury handled through downtime

Decision:

Normal mission cadence includes approximately 2–4 weeks between operations.

Minor wounds recover naturally during this period. More severe wounds add extra downtime rather than requiring substitute characters.

## Relationship tone

Decision:

The trio may argue and irritate one another, but their baseline relationship includes professional trust and comradeship.

They entrust their lives to each other.

Relationships are about:

- closeness
- chemistry
- arguments
- friendship
- reconciliation
- personal history
- possible romance
- value conflicts

They are not a system for making combat AI intentionally unreliable.

## Relationship does not choose tactical support

Explicitly rejected:

- relationship-based healing priority
- relationship-based covering priority

Reason:

Those behaviors are tactically irrational and undermine the team's professional identity.

## Combat AI principle

Decision:

Characters always attempt to follow the pre-mission plan and perform the best tactical action available.

Character differences affect execution quality, not willingness to behave professionally.

## Planning complexity

Decision:

Do not build a Door Kickers-style detailed path-planning game.

Use lightweight tactical policies similar in spirit to PMM.

## Loadout customization depth

Decision:

Use approximately **Door Kickers 2-level equipment depth**.

For normal firearms, the default customization axes are:

- muzzle
- optic
- ammunition type

Primary and secondary weapons may both use this structure where applicable.

Do not expand into a detailed gunsmith with stocks, grips, handguards, internal parts and other granular attachment slots unless there is a later gameplay reason.

## Final character loadout slots

Decision:

Each protagonist has:

- primary weapon ×1
- secondary weapon ×1
- armor ×1
- tactical gear ×2
- specialist gear ×1

Tactical gear covers compact consumables/common mission equipment such as grenades and small medical kits.

Specialist gear is the main role-defining equipment slot and may hold breaching tools, large medical gear, reconnaissance systems, heavy/special weapons, sensors, shields or similar mission equipment.

Reason:

With three fixed protagonists, 2 tactical slots per character give the team six flexible small-equipment choices, while one specialist slot per character creates meaningful temporary roles without hard classes.

## Ammunition and throwable quantity abstraction

Decision:

Follow PMM's general simplicity for ammunition and throwables.

- Player chooses ammunition **type**, not magazine count.
- Player chooses throwable **type/item**, not how many individual grenades are packed.
- Mission quantities are defined internally by the selected equipment/item.
- No magazine-by-magazine or grenade-by-grenade packing UI.

Reason:

Manual quantity packing adds inventory-management complexity without serving the intended fast pre-mission preparation loop.

## No dedicated medical slot

Decision:

Medical gear competes with other tactical or specialist equipment.

Do not create a permanent medical slot that effectively forces one protagonist to become the team's fixed medic.

## No granular headgear / rig slots by default

Decision:

Do not separately customize helmet, NVG, ear protection, belt, carrier components, etc. by default.

Abstract those through armor, mission conditions or specialist gear unless later playtesting demonstrates a real tactical need.

## Loadout UX reference

Decision:

Use Door Kickers 2's customization screen as the primary UX reference for loadout editing:

- weapon and its small modification slots are visually grouped
- primary and secondary weapons use the same basic interaction pattern
- armor and mission gear live in the same character loadout context
- clicking a slot exposes compatible alternatives
- comparison information should be immediately visible

Copy the interaction principle and information hierarchy, **not** proprietary art or an exact pixel-for-pixel layout.

## PMM reference use

Decision:

Use PMM's combat, customization, progression, planning UI, map structure and camera design as reference material.

Do not directly copy proprietary content or code into the project.
