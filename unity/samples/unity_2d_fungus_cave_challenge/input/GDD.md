# Fungus Cave Expedition — complete three-floor survival roguelike

## Delivery
Build the full playable game below and the mandatory `game-session/v1` service.
Automated acceptance uses that service for chapter entry, legal save preparation
and real actor identity. Missing/incorrect capabilities are incomplete delivery
and prevent acceptance of affected requirements, not a separate optional feature.
Players must be able to play the whole game without service calls.

## Source and bounded adaptation
This task is a new presentation of Bozar/FungusCave's interconnected systems,
not an exact port. It retains three-floor combat, energy, infection/stress,
potion economy/revival, nine powers and fungus/beetle pressure. CONTENT.json
fixes three compact but complete authored floors with 12/14/16 potion-bearing
enemies instead of the original forty per floor. No auto-explore, wizard mode,
external settings editor or original third-party font is required.

## Player experience and rules
- FC-01: A title has New Game, Continue when a manual save exists, instructions
  and quit/menu navigation. Three distinct floors contain connected walkable
  space, impassable walls, water pools, fungi, enemies and an exit. Use the fixed
  maps and enemy content, not a single placeholder arena. Rows in content are
  top-to-bottom; world grid cell (x,y) uses bottom-left (0,0), +y upward.
- FC-02: Arrow keys/WASD move cardinally; Q/E/Z/C move diagonally; Period waits.
  Each key press causes one action, not uncontrolled repeat. Bumping an enemy
  attacks it instead of entering its cell. No actor moves through a wall or
  shares a cell with another live actor. Leaving the board is blocked.
- FC-03: Player starts HP10, potions2 (cap4), energy4000, stress0, no infection,
  no purchased powers. An action needs energy>=3000. Moving costs1000,
  attacking1400; diagonal adds400, leaving a pool adds400, Slow adds800.
  If energy is too low, that key spends one waiting turn, with no requested
  move/attack. A blocked wall move costs no energy and no turn.
  After an accepted move/attack/wait (including forced wait), player energy
  restores1000 plus active power bonuses, capped4000. Turn increments once.
- FC-04: Every accepted player turn each live enemy gains1000 energy (cap4000).
  At >=3000 it performs at most one action: adjacent bump attack, otherwise one
  cardinal step toward the player on free floor; subtract the matching
  move/attack cost. Deterministic x-first path choice is acceptable. Enemies
  cannot pass through walls, each other or the player. Sleeping/stationary
  visuals must not substitute for enemy turns and real attack damage.
- FC-05: Base player damage2; Weak reduces attack damage by1 (minimum1).
  Enemy HP/damage/reward are in content. Killing removes the actual enemy and
  grants its potions up to cap4; Mutated enemies grant one extra. Dead enemies
  never attack again. At HP<=0 automatically spend one potion and revive in
  place with HP10 (HP5 if Mutated), energy4000 and stress reduced by9 to min0.
  With no potion, enter a stable defeat result. Potion spending on powers
  therefore competes with future survival.
- FC-06: Each successful attack has a seeded 40% infection chance, raised to80%
  if the victim is in a pool or below half maximum HP. For the player, the first
  three infection events increase stress rather than infect. Immunity raises
  this threshold to4 while active. Further infection applies a seeded random
  Slow, Weak or Mutated for5 turns. Re-infection extends current duration by1
  to cap9. Existing infection recovers1 per accepted turn (2 with Fast Heal),
  clearing type at zero. Enemy infections do not use stress.
- FC-07: A visible shop lists all nine powers, costs and prerequisite.
  Vigor/Immunity/First Aid cost2; Adrenaline/Fast Heal/Patient Zero/Siphon/Plague/
  Bleed cost4. Adrenaline requires Vigor, Fast Heal requires Immunity,
  Patient Zero requires First Aid. Cannot buy twice or without funds/prerequisite;
  reject with visible feedback and no charge. Buying does not advance combat.
  Three loadout slots can each hold one distinct purchased power or empty.
  Newly bought powers enter the first empty slot. Clicking a slot cycles
  through owned powers not used in another slot, then empty. A slot's power
  is active only at stress>=its slot number (1,2,3).
- FC-08: Active Vigor adds200 energy/turn. Adrenaline adds200, or400 at HP<5.
  First Aid heals1/turn only below HP5; Patient Zero heals1 only while infected
  and below HP8. Fast Heal/Immunity affect infection as above.
  Siphon subtracts player damage*300 from the attacked enemy's energy to min0.
  Plague adds20 percentage points to player infection probability, cap100%.
  Bleed adds1 player attack damage. Purchased but inactive powers have no effect.
- FC-09: Beetle counter starts30. Each non-beetle kill and each player revival
  reduces it by1, by2 for a victim adjacent (8-neighborhood) to fungus.
  At zero spawn up to four HP3/damage1/no-potion beetles on nearest free
  walkable cells around the player and reset counter30. Show a warning at<=4.
  Beetles act normally but do not themselves lower the counter or count as
  potion-bearing enemies for floor clearance.
- FC-10: The exit opens only when every potion-bearing enemy on that floor is
  dead. The player must actually move onto it to enter the next floor, carrying
  HP/potions/stress/infection/powers/loadout; reset local enemy content, turn,
  beetle counter and energy. Clearing floor3 and entering its exit wins.
  Merely restoring a nearly-cleared save never grants the next floor or win.
- FC-11: Escape/visible Pause freezes combat and input; Resume preserves state.
  Restart works from play/pause/defeat/victory and starts a clean floor1 run.
  Menu returns to title. Repeated transitions must not duplicate actors/input.
- FC-12: Save is available in active play and stores the real campaign state.
  A new process opens the menu, not automatically in combat. Continue restores
  the manual save, including floor, resources, actors and loadout, and permits
  normal play. Restart does not silently resume the old save.
- FC-13: Present a coherent dark cave with distinguishable floor/wall/water/
  fungus/exit/player/enemy/beetle sprites, visible damage/death and infection
  feedback, readable HP/potions/stress/turn/floor/remaining-enemies/loadout HUD,
  explanatory shop and result overlays. All displayed values agree with play.

The public state rules are authoritative in SESSION_MODEL.json. Content and
asset paths are in CONTENT.json and ASSET_CATALOG.md; do not obtain upstream
gameplay source. Internal architecture and development strategy are yours.
