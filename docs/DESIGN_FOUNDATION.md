# Design Foundation

Status: early planning

## 1. Fantasy

Three friends form a small armed contract team because they want to make money.

They are not running a corporation. There is no hiring department, employee roster, corporate management layer, or disposable mercenary pool.

The fantasy is:

> Keep the same three people alive, improve them over time, buy and configure better equipment, prepare for the next job, and watch them carry out the plan.

## 2. Party structure

- Fixed cast: **3**
- Standard deployment size: **3**
- No bench roster in the current design.
- All three are protagonists rather than replaceable units.

This intentionally trades party-selection breadth for stronger attachment, clearer characterization, lower content overhead, and deeper pair relationships.

## 3. Combat philosophy

The player sets intent before combat. The characters execute it.

### Player responsibility

- Choose equipment.
- Choose weapons and weapon configuration.
- Develop each character over time.
- Set lightweight tactical policies before deployment.
- Evaluate mission information and risk.

### AI responsibility

During combat the team should perform the best tactical action available within the player's plan.

The AI should handle:

- threat detection
- target selection
- cover selection
- route selection
- spacing
- aiming and firing
- reloading
- grenade use
- healing timing
- breaching / door interaction
- adaptation when the situation changes

### Critical rule

**Character personality and relationship values must not cause deliberately unprofessional tactical behavior.**

Examples that are explicitly rejected:

- healing a close friend before a more urgent casualty because of affection
- covering a friend more often because of friendship
- refusing support because of an argument
- reckless solo pushes caused by a personality tag
- lowering combat competence to create drama

Character differences in combat should come from capability, equipment and learned skills—not irrational sabotage of doctrine.

## 4. Pre-mission planning

Planning should stay light.

The game is not trying to become Door Kickers' detailed waypoint-planning system.

The intended interaction is closer to defining doctrine than plotting precise movement paths.

Potential policy categories:

- engagement posture
- fire policy / target focus
- grenade usage
- healing threshold
- breaching method
- risk-direction awareness

The exact number and wording are not yet final.

## 5. Equipment and loadout depth

The target customization depth is approximately **Door Kickers 2 level**: enough choices to create meaningful tactical tradeoffs without turning the game into a gunsmith simulator.

### Firearm structure

Each primary and secondary firearm should generally expose only three attachment/configuration axes:

1. **Muzzle**
2. **Optic**
3. **Ammunition type**

The player chooses ammunition **type**, not magazine count or individual round quantity.

Ammunition carried into a mission is abstracted / preset by the game in the same general spirit as PMM. Do not turn ammunition into manual inventory packing.

Not every weapon must support every option, and some weapons may have fixed components.

Avoid adding extra slots such as stocks, grips, handguards, rails, triggers, gas systems, internal parts, etc. unless later testing proves that they add meaningful tactical choices.

### Character equipment structure

Each protagonist has the following major loadout slots:

- **Primary weapon ×1**
- **Secondary weapon ×1**
- **Armor ×1**
- **Tactical gear ×2**
- **Specialist gear ×1**

Tactical gear is for compact consumables or commonly carried mission tools, for example:

- fragmentation grenade
- flashbang
- smoke grenade
- compact individual medical kit

For consumables such as grenades, the player selects the **item/type**, not a manually packed quantity. Each equipment item defines its own mission allowance internally.

Specialist gear is the principal role-defining slot, for example:

- breaching charge
- lock / cutting tools
- large medical kit
- reconnaissance drone or camera
- grenade launcher or mission-specific heavy weapon
- anti-armor weapon
- shield
- sensor / communications gear

The specialist slot is intended to create temporary mission roles without hard character classes.

### Equipment-effect model

Follow **Door Kickers 2-style direct item effects**, not a separate player-facing encumbrance simulation.

The player does **not** manage:

- kilograms
- carry-capacity limits
- load percentages
- magazine weight
- grenade weight
- manual weight budgets

Instead, each selected item directly changes the relevant combat properties.

Examples:

- heavier armor directly reduces movement / turning while increasing protection
- a long or heavy weapon directly reduces handling
- optics directly change aim/readiness behavior at relevant ranges
- suppressors directly change sound and handling characteristics
- specialist equipment may directly impose a mobility or handling penalty

The UI should show the **resulting effects of the selected loadout**, not require the player to calculate why those effects occurred.

### Firearm stat presentation

Follow Door Kickers 2's player-facing firearm stat model.

Show these five primary firearm stats:

- **Aim Speed**
- **Accuracy**
- **Critical / Lethality**
- **Reload Speed**
- **Maneuverability**

Aim Speed, Accuracy and Critical/Lethality should be represented as **distance-dependent curves or graphs** rather than a single universal number when practical.

Reload Speed and Maneuverability should be shown as compact scalar bars / ratings.

Do not expose every internal firearm variable to the player. Internal values may remain much more detailed, but the loadout UI should summarize them through these few readable outputs.

### Slot philosophy

Do **not** create dedicated class-forcing slots such as a mandatory medical slot.

If a player wants more medical capability, it should consume tactical or specialist capacity and therefore compete with other useful equipment.

Helmet, NVG, ear protection, belt, plate carrier components and similar individual pieces are not separate default customization slots. Keep them abstracted into armor, mission conditions, or specialist equipment unless a strong gameplay reason appears later.

Do not expose magazine-by-magazine ammunition packing or grenade-count packing to the player.

Do not expose a separate weight-management system.

### UX target

Door Kickers 2 is the current reference for the customization interaction pattern:

- character remains the context
- large primary/secondary weapon selection
- small attachment buttons directly associated with the equipped weapon
- armor and gear choices presented in the same loadout view
- selecting a slot opens the valid alternatives for that slot
- stat differences should be immediately readable
- swapping an item should immediately show resulting mobility / handling / protection changes

Use the **interaction model and information hierarchy** as reference, not its proprietary graphics or exact layout.

The goal is that a player can understand and change a character's complete combat loadout without navigating a multi-level gunsmith interface.

## 6. Character relationships

The three characters can argue, annoy one another and disagree on values, but they are still comrades who trust each other with their lives.

Desired tone:

> They may fight over stupid things off-duty, but when bullets start flying they do their jobs and protect the team.

Relationships represent emotional closeness and chemistry, **not willingness to perform professional duties**.

### Relationship outputs

Relationship state may affect:

- dialogue
- downtime events
- friendship scenes
- arguments
- reconciliation
- personal-history reveals
- value conflicts
- romance, if used
- reactions to injury or death
- story choices / endings

Relationship state should generally **not** grant direct combat-stat bonuses.

Avoid systems such as:

- +5% accuracy for friends
- faster healing because the target is liked
- extra cover probability for a close friend

The reward for relationship development should primarily be **content and characterization**.

### Relationship topology

With three protagonists there are only three pair relationships:

- A ↔ B
- B ↔ C
- C ↔ A

This allows each relationship to be written deeply instead of generating many shallow pair combinations.

## 7. Injury and time

A fixed three-person team creates a roster problem if injuries routinely prevent deployment.

Current solution: contracts are separated by meaningful downtime.

Baseline:

- After a mission, roughly **2–4 weeks** pass before the next operation.
- Minor injuries normally recover during that period.
- More serious injuries increase downtime.
- Extremely serious wounds can become major narrative events.

Thus injury primarily costs **time**, rather than forcing the player to recruit substitutes.

Possible consequences of extra downtime:

- contracts expire
- new contracts appear
- story state advances
- relationship / downtime events trigger
- financial opportunities change

Exact calendar mechanics are not yet designed.

## 8. Progression philosophy

The same three characters should be configurable into different roles between missions.

Avoid hard class locking.

A character can have natural strengths, but equipment and training should allow substantial role flexibility.

Progression layers:

1. **core attributes**
2. **weapon proficiency**
3. **field proficiency**
4. **traits unlocked by proficiency**
5. equipment and weapon configuration

There is no separate qualification/certification system.

There is also no default perk-point / skill-tree currency. Traits should be earned organically from training and proficiency progression.

Field proficiency is divided into exactly five current categories:

1. **CQB**
2. **Medical**
3. **Breaching**
4. **Tactical Gear**
5. **Fieldcraft**

Weapon proficiency is tracked separately.

Do not create a separate "Tactics" proficiency. Tactical judgment is part of the competent AI baseline; proficiency affects execution quality rather than making low-skill characters choose irrational tactics.

The exact core-attribute list, proficiency thresholds and trait list are **not final**.

## 9. Scope discipline

Avoid rebuilding the management layers that made the concept larger than necessary.

Currently excluded:

- company management
- hiring / firing
- random mercenary generation
- large roster management
- office staffing
- corporate reputation simulation for its own sake
- base-building unless later justified by the core loop
- deep gunsmith-style weapon assembly
- granular helmet / carrier / belt component simulation
- manual ammunition / grenade quantity packing
- player-facing weight / encumbrance management

The game should remain centered on:

**three characters + preparation + automatic tactical combat + progression + character story.**
