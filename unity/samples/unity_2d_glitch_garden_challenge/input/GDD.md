# Glitch Garden Siege — complete five-level lane defense

## Delivery
Deliver the complete game and required `game-session/v1` service. Automated
acceptance uses chapter entry, legal saves and real actor roots; missing or
incorrect services make affected delivery incomplete. Normal play uses only UI.

## Source adaptation
Based on CompleteUnityDeveloper/07-Glitch-Garden. Retain five-lane placement,
four defender roles, star production/economy, lane targeting and projectiles,
lizard attacks, fox vaulting, lives, timed waves with cleanup, five-level
progression and complete lifecycle. CONTENT.json fixes a bounded campaign.
The art supplied here is newly authored; original fonts, sound recordings and
third-party art are deliberately not redistributed.

## Rules
- GG-01: Title offers Play, level selection, Options and instructions. Five
  distinct levels use a board of5 lanes by8 cells, cell centers (column+1,row+1)
  in world coordinates, row0 bottom. Start stars300, lives5; empty board.
  Enemies enter from x10 and leave at x0. Content defines all waves/timing.
- GG-02: Four mouse-selectable defender cards show role/cost/selection:
  Cactus100 (HP100, projectile20 every1s), Gnome150 (HP100, projectile35 every2s),
  Gravestone75 (HP300, no attack), Trophy50 (HP80, stars+50 every5s).
  Selecting a card does not charge. Clicking an empty cell places exactly one
  selected defender and deducts its cost once. Occupied cells or insufficient
  balance are rejected without replacing anything or charging; show feedback.
- GG-03: Trophy production begins after a full5s, repeats while alive, and stops
  on death/pause/results. Other roles do not produce stars. At least two
  defenders/enemies in different lanes can act simultaneously.
- GG-04: A Cactus/Gnome fires only while a live enemy lies to its right in the
  same lane. Use real visible rightward projectiles at speed6, damage as above,
  which hit the first live enemy crossed in that lane exactly once and disappear.
  Empty/other lanes do not trigger shooting; enemy death removes its blocking/
  attacking behavior. Do not replace projectiles with invisible instant damage.
- GG-05: Lizard HP100/speed0.45 moves left, stops within0.65 of the first defender
  in its lane and attacks for20 each1s. Resume moving when it dies.
  Fox HP120/speed0.65 does the same to non-Gravestones but vaults past each
  Gravestone without damaging it, using an observable jump/lift/animation and
  landing on its left. Off-lane defenders never stop an enemy.
- GG-06: A leaked enemy at x<=0 removes exactly one life and disappears. At
  lives0 immediately lose, stop gameplay, and present Retry/Menu.
  Waves spawn only according to the current level's schedule. Timer reaching
  duration stops spawning but does NOT win while any live enemy remains.
  Once duration reached and all enemies removed, show stable victory.
- GG-07: Next from victory starts the next real level with its new waves,
  empty defenders/projectiles, stars300, lives5 and time0. After level5 show
  campaign complete. All five levels are normally selectable/playable;
  progress indicators persist across processes.
- GG-08: Escape/visible Pause freezes movement, attacks, projectiles, production
  and timer. Resume continues exact state. Retry from play/pause/loss/win resets
  only the current level, preserving campaign progress. Menu and repeated
  level changes do not duplicate UI, enemies, projectiles or input listeners.
- GG-09: Options from menu allows a visible volume toggle (0 or1) and Return.
  Use newly generated/simple audio or engine synthesis for firing, damage,
  placement and result events; mute affects actual audible channels.
  Volume and completed-level bits persist on a fresh-process menu.
- GG-10: A readable HUD shows level, stars, lives, elapsed/duration and remaining
  wave/enemies. Card selection, placement, unaffordable/occupied rejection,
  trophy production, projectile hits, defender/enemy death, fox jump, leak,
  pause and win/loss each have player-visible feedback. Build a coherent
  stylized garden with contrasting lanes and clearly different actors using
  the supplied role sprites. Controls must be visible and genuinely mouse-operable.

Session and technical details are indexed by README.md. No original gameplay
implementation is supplied; complete the whole campaign, not a static board.
