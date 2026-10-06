# Door Kickers 2 Reference Notes

Source reviewed: local Door Kickers 2 v1.11 data supplied by the project owner.

This file records only design/structure observations useful to this project.

## Equipment slot model

The game's equipment documentation defines the main inventory categories:

- PrimaryWeapon
- SecondaryWeapon
- Armor
- UtilityPouch
- SupportGear1/2/3

Only some support slots are intended for direct player customization; others can represent always-equipped support tools.

## Firearm customization

The customization UI explicitly contains modification slots for both primary and secondary weapons:

### Primary
- PrimaryWeaponMuzzle
- PrimaryWeaponScope
- PrimaryWeaponAmmo

### Secondary
- SecondaryWeaponMuzzle
- SecondaryWeaponScope
- SecondaryWeaponAmmo

The equipment data confirms these are functional categories rather than cosmetic placeholders.

Examples observed:

- optics are separate `Scope` entries bound to weapon scope slots
- suppressor-equipped weapon variants use the muzzle inventory binding
- ammunition is represented as separate ammo entries and can alter damage, penetration, accuracy and other weapon behavior

For this project, the important lesson is the **three-axis abstraction**, not Door Kickers 2's exact implementation technique.

## General gear

Observed gear categories include:

- armor
- grenades in utility pouches
- smoke grenades
- flashbangs
- breaching explosives
- lock tools
- breaching tools
- specialist support weapons / gadgets

This is an appropriate complexity target for the new game's equipment layer.

## Customization UX

The supplied `customization.xml` shows a compact single-character loadout screen where:

- the primary weapon is a major selection element
- its muzzle, optic and ammunition modifications are shown as smaller associated controls
- the secondary weapon mirrors that structure
- armor and additional equipment slots continue in the same screen
- equipment statistics and comparison bars are displayed alongside selection

This avoids a separate deep gunsmith screen and keeps the player focused on the character's complete mission loadout.

## Adaptation for this project

Adopt:

- compact slot hierarchy
- direct association between weapon and its three modifications
- one loadout context per protagonist
- fast comparison and swapping
- limited but tactically significant options

Do not adopt:

- exact UI artwork
- exact textures/icons
- exact XML/data structures
- exact weapon stats
- exact item names/content lists as a copied dataset
- Door Kickers' detailed waypoint-planning gameplay
