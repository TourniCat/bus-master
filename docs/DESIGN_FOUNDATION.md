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

The game is not trying to become Door Kickers.

The intended interaction is closer to defining doctrine than plotting precise movement paths.

Potential policy categories:

- engagement posture
- fire policy / target focus
- grenade usage
- healing threshold
- breaching method
- risk-direction awareness

The exact number and wording are not yet final.

## 5. Character relationships

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

## 6. Injury and time

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

## 7. Progression philosophy

The same three characters should be configurable into different roles between missions.

Avoid hard class locking.

A character can have natural strengths, but equipment and training should allow substantial role flexibility.

Likely progression layers:

1. core attributes
2. weapon proficiency
3. perks / specialties
4. equipment and weapon configuration

The exact attribute list is **not final** and should be reconsidered during renewed planning.

## 8. Scope discipline

Avoid rebuilding the management layers that made the concept larger than necessary.

Currently excluded:

- company management
- hiring / firing
- random mercenary generation
- large roster management
- office staffing
- corporate reputation simulation for its own sake
- base-building unless later justified by the core loop

The game should remain centered on:

**three characters + preparation + automatic tactical combat + progression + character story.**
