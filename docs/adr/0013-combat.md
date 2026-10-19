# ADR-0013: Resolve combat once per tick, after everything has moved

- Status: Accepted
- Date: 2026-10-19
- BUILD.md sections:
  - 6, every table: the Taper, Flame, Kindling, Parry, Spells, Hit feedback, Enemy-side rules;
  - 5, Pogo ("on hitting an enemy, hazard or pogo-able surface");
  - 13, the frame order ("input, simulation, presentation").
- Checklist lines (BUILD.md section 15, Combat):
  - "Attack comes out on frame 3 from a neutral press, every time, including during hitstop";
  - "Dash cancels an attack on frame 4 and never eats the next attack input";
  - "3-hit chain ... reads as three impacts with rising weight";
  - "Parry succeeds on the 8-frame window ... 10 times in a row";
  - "Unparryable red distinguishable from parryable white at Pitch with flashes at 0";
  - "Taking a hit is never confusing";
  - "Hitstop never causes a dropped input; buffered inputs fire on the first free frame";
  - "A kill releases an ember that reaches the player within 20 frames; Flame reacts";
  - Graphics and feel, "Screen shake at default 50% never moves the frame more than 3 units".

## Summary

- Each tick: input, player step, enemy steps, then `Combat.resolve` (effects age, player hits, enemy hits); player hits win a tie (see Order within a tick).
- One strike, one hit: every strike, spell and pogo has a serial and an enemy keeps the last; Blaze trails burn once per strike (see One strike, one hit).
- Flame: 11 per Taper hit, 8 per pogo, 33 per parry, 11 per kill ember (arrives in 16 ticks); Kindling +1 per hit, +5 per parry (see Damage, Flame, Kindling).
- Hitstop: light 2 f, finisher 4, Charged 6, parry 12, kill 3 or more, player hit 8 (player only); damage over 30 adds 1 f per 10, capped at 8 (see Hitstop).
- A hit takes poise equal to its damage; at 0 the enemy staggers 30 f; knockback bleeds at `knockback_decel` 2400 u/s2 (see Poise, Knockback on enemies).
- Parry: an attack press no older than 7 player frames when a parryable box touches; spends the press; 0 damage, +33 Flame, +5 Kindling (see Parry).
- Player hit: a heart lost, Kindling down a tier, 8 f hitstop, 300 u/s knockback for 12 f, 20 f invulnerable; hazards cost a heart (see The player hit).
- Charged strike: hold attack 24 f then release, 36 damage; Kindle costs 33 Flame, Radiance 66 at Blaze, Mend 33 (see The Charged strike, Spells).
- Enemies are simulated bodies; a telegraph is at least 20 f, and `telegraph_cue` fires exactly 20 ticks before the swing lands (see Enemies).
- Presentation only reads the core: shake capped at 6 u (scaler 50%), flash 0.55 opacity, all effects through the VFX budget (see Presentation).

## Context

BUILD.md section 6 gives the strikes' frames, the resources and the feedback table, but leaves open how a tick resolves hits, how long a parry press counts, what Mend and Radiance are bound to, how a Charged strike is asked for, what knockback does to the player's control, what a hazard costs once there are hearts, and what dying does before the run loop exists.

## Decision

**Order within a tick** (`core/sim/simulation.gd`): the input frame enters the ring; the player steps (movement, then any strike, spell or Mend that starts this tick); every enemy steps (its state machine and its move); then `Combat.resolve` compares boxes where everything ended the tick:
1. effects age: kill embers fly and grant their Flame on arrival, Blaze trails burn out, burning enemies take their burn damage;
2. the player's hits: the strike box, Kindle's cone, Radiance's burst, the pogo box, the Blaze trails;
3. the enemies' hits on the player.

The player's hits come first, so a strike that kills or staggers an enemy on the tick its attack would land takes that attack away. Hitstop set by a hit counts from the next tick.

**One strike, one hit.** Every strike, spell cast and pogo has a serial; an enemy keeps the serial of the last one that hit it, so a strike whose box stays on an enemy for all its active frames hits it once. A Blaze trail burns each enemy once per strike: an enemy keeps the serials of the strikes whose trails have burned it until those trails go out, so the overlapping trails of a chain each burn it once (first review, H2: with one remembered serial the two strikes' trails took turns and burned every tick, 94 damage where 34 was due). The dead are skipped by every hit: a dead enemy has no hurtbox, and an empty rect at the room's origin used to count as inside any box over it (M7).

**Damage, Flame, Kindling.** Damage is the Taper table's, plus the Kindling tier's bonus (+10%, +20%, +30%, rounded to the nearest point). Each Taper hit grants 11 Flame, each pogo off an enemy 8, each parry 33. A kill releases an ember that flies to the player in 16 ticks (a smoothstep along the line to wherever the player is, so it can never miss) and grants 11 Flame when it arrives (`flame_per_kill`, new: BUILD.md says "+Flame" without a number). Every hit that lands adds one to Kindling; a parry adds 5.

**Hitstop** (`content/combat/combat.tres`): light 2 f, finisher 4 f, Charged 6 f, parry 12 f, each on both; a player hit 8 f on the player only; a kill at least 3 f. Damage above 30 adds 1 f per 10 damage, capped at 8 f. A frozen player's input keeps landing in the ring (ADR-0004), so a press made during hitstop fires on the first free frame and a strike pressed there has its box on its frame 3 counted from that frame.

**Knockback on enemies** is a horizontal speed along the hit (the Taper table's u/s) that bleeds off at 2400 u/s² (`knockback_decel`, new), stopping at walls. Light enemies are launched by finishers (600 u/s up, `finisher_launch`, new) and juggled by up-strikes (their 200 u/s, up). Side 1 recoils the player 60 u/s away from the hit.
- Damage that is not a hit (a burn tick, a Blaze trail, a finisher's Blaze burst) takes health and poise only: it never touches the knockback. At Blaze a strike's own trail burns the enemy on the tick the strike lands, and it used to set that strike's knockback to nothing (first review, H1). A kill by it still has the Kill row's 3 f of hitstop on both, as a strike's kill does.
- A corpse carries momentum (BUILD.md, Kill): it keeps the killing hit's knockback and launch, slides, falls and comes to rest; the dummy comes back whole at its room marker, at rest. A corpse used to stop dead where it died, in mid-air too (H5).

**Poise.** A hit takes poise equal to its damage; at 0 the enemy staggers for 30 f, its attack is cancelled, and its poise resets.

**Parry.** A parry is an attack press, consumed or not, no older than 7 player frames on the tick a parryable attack's box first touches the player's hurtbox: the 8 frames that end with the hit landing. The parry spends the press (`InputRing.spend_presses`): it parries every swing that lands on that tick, and none after. The parry's 12 f of hitstop hold the press's age still, and the same press used to parry every swing that landed in them (first review, H4). A press made during that hitstop is a fresh one. Content refuses a window longer than the input ring holds (L2). A failed parry is just an attack (the press also starts a strike, as any press does). The window is the enemy attack's, so it is never a guess: the dummy's swing lands on its frame 25 (24 f telegraph), and pressing on frames 18 to 25 parries. A parry: 0 damage, 12 f of hitstop on both, the enemy knocked back 200 u/s and staggered 40 f, +33 Flame and +5 Kindling. A red attack is never parried; it hits.

**The player hit.** An enemy attack's live box touching the hurtbox of a player who is not invulnerable lands once per attack:
- hearts drop by the attack's damage, and Kindling drops one tier;
- the strike, spell or Mend under way ends (a Mend's Flame is lost);
- 8 f of hitstop on the player only, then a knockback of 300 u/s away from the attacker for 12 f (`player_hit_knock_frames`, new), during which the stick's horizontal is ignored (as after a wall-jump) but every action is free: a dash, jump, strike or toss pressed during the hit fires on the first free frame and ends the knockback;
- 20 f of invulnerability, counted in the player's own frames as the parry window is: it starts after the hit's 8 f of hitstop, so it covers the 12 f of knockback and 8 f beyond (28 ticks of the world from the hit; first review, M5, read "from the hit" as 20 ticks: the window is what the player lived through).

**Hazards cost a heart.** Spikes and other hazards send the player back to safe ground (ADR-0010) and now cost 1 heart as a hit does (Kindling drops a tier; the hit's feedback plays). BUILD.md leaves this open; a hazard that costs nothing makes the spike pits of techs 3 and 4 free to fail.

**Death** (Phase 1 only: the run loop arrives later). At 0 hearts the player is sent back to the room's spawn with full hearts, 0 Flame and Kindling reset ("Dying resets it").

**The Charged strike.** A press always starts side 1 at once (the checklist's frame 3). Holding attack on, unbroken, for 24 frames arms the Charged strike; letting go then asks for it, and the request waits in the attack buffer (8 f) like a press: it starts as soon as the strike layer is free, in the direction the stick held on the release (kept with the request: it used to read the stick on the frame the strike started, first review M4). A press on a frame the button also reads as held (let go and pressed again inside one tick) starts a new hold (L1). 3 f startup, 6 f active, 14 f recovery, 36 damage, 400 u/s; a dash cancels it from its frame 8. At Kindling White every tenth hit is a Charged strike (its damage, knockback and hitstop) whatever strike landed it.

**Spells** run in their own layer beside locomotion, like strikes: the player keeps moving, and no strike or other spell starts while one runs.
- A spell press waits in its 8 f buffer while a strike or another spell runs; one older than that when the layer frees is gone, as a jump pressed early in a long strike is (first review, M3, asked for a press that waits however long: kept as the buffers' one rule and put to the director). A spell press during a dash casts from dash frame 6, ending the dash; one that fizzles for want of Flame leaves the dash alone (M6).
- **Kindle**: a spell press (buffered 8 f) with 33 Flame. Its direction is the stick's on the press frame, read four ways: up, down (in the air only; down on the ground is the floor) or forward. 4 f startup, 6 f active, 10 f recovery; from its frame 8 a dash, jump, strike or toss cancels it. The cone is three rectangles end to end along the 180 u, 40, 68 and 96 u wide (CLAUDE.md rule 8; `kindle_sections`, `kindle_width_near_u`, `kindle_width_far_u`, new). 30 damage; it ignites: a burning enemy takes 2 damage every 15 f for 90 f, and a new ignition restarts the burn (`burn_*`, new).
- **Radiance**: a spell press with the stick held down, on the ground, at Kindling Blaze or above, with 66 Flame. 6 f startup; on its frame 7 every enemy is pushed 400 u/s away and the room is lit for 300 ticks (5 s); 12 f recovery (new). Below Blaze, or in the air, the same press is a Kindle. Actions wait out the startup; one on the burst frame ends the spell, and the burst still comes that frame (`Player.radiance_burst`): it used to be lost, the 66 Flame spent for nothing (first review, H3).
- **Mend**: a Mend press on the ground with 33 Flame and a heart missing. The Flame is spent at once; Ash stops where Mend starts (a hit's knockback ends with it) and channels standing still for 50 f, then heals 1 heart. Letting go of Mend, a jump, dash, strike, spell or toss, or a hit ends the channel and the Flame is lost; a spell pressed during Mend casts at once (first review, M2, where it waited and dropped). Still held at the end, with the Flame and a heart to heal, the next Mend starts at once. The stick is ignored only while the channel goes on: on the frame Mend is let go or ended by an action, it turns and moves Ash at once (H6: that frame was dead). A spell or Mend, like any action, ends a hit's knockback (M1).
- The Ember Toss is unchanged (ADR-0010).

**White** also lifts the ground dash's cooldown ("dash has no cooldown"). **Blaze**: each tick a strike's box is live it leaves its box behind as a fire trail for 10 f that deals 4 damage once to each enemy it touches (`blaze_trail_damage`, new); a finisher's hit also burns every other enemy within 96 u for 8 (`blaze_aoe_*`, new).

**Enemies** are simulated bodies in the collision world (`core/enemies/enemy.gd`), never Godot physics. An attack runs telegraph, active, recovery; content validation refuses a telegraph under 20 f.
- **The telegraph cue** (`SimEvents.TELEGRAPH_CUE`, `telegraph_cue_frames` 20, new): sent on the tick the swing lands in exactly 20 ticks, for the telegraph's sound (BUILD.md section 11: "every telegraph has a sound 20 f before the hit"). From the cue the attack is committed: hitstop on the enemy (a hit during its last 20 telegraph frames) no longer delays the swing, so it lands exactly when the sound said; before the cue a hit's hitstop delays the telegraph and the cue with it (first review, presentation M4: the sound played on the telegraph's first frame, 24 or more before the hit). `Enemy.ticks_to_landing` gives the ticks left, hitstop counted. The training dummy (`training_dummy.gd`, room entity `entity dummy`) stands, faces the player, takes hits, staggers and comes back 60 ticks after a kill; with `attack=1` it swings every `period` ticks (white, or red with `red=1`).

**Presentation** reads the simulation and its events once per tick and never writes it:
- `game/feedback/hit_feedback.gd`: directional shake capped at 6 u with a global scaler (default 50%) on the drawn camera only, never the rig; the parry's full-screen flash at 0.55 opacity (`flash_alpha`; a solid white frame hid the parry it marks); the Charged hit's chromatic split; the red vignette for a hit or a hazard; slow motion through the driver; hit sparks, smears, bursts and Radiance's ring through the VFX budget manager, and sounds through the voice priority system (Phase 1 placeholders synthesized in code). Rules, each pinned by a test:
  - **Flash setting.** A flash or split lasts its tuned ticks (1) whenever the setting is above 0 and the setting scales only its opacity; at 0 nothing flashes (`test_the_flash_setting_scales_the_opacity_never_the_duration`).
  - **One hit, one bright thing.** A hit's spark, smear and burst (and the stagger burst it causes) are one group in the budget: they share the 100 u cell, so a finisher's arc and burst are not refused by the hit's own spark. Another hit's effects still compete for the cell by priority. A burn (burn tick, Blaze trail, the finisher's AoE) carries `VfxBudget.BURN`, below `HIT` and the player's `PLAYER`, so it never displaces a Taper or spell spark; Radiance's burst and ring carry `SPELL`, above everything, so they show whatever spark the cell holds.
  - **Screen space through the budget.** The full-screen flash and the chromatic split share one bright slot, admitted by `VfxBudget.claim_screen` at most once per 3 ticks (`vfx_screen_frames`; a newcomer replaces the holder only if it is more important); the vignette is a dark edge, always admitted, a new one restarting the old. `feedback_overlay.gd` draws what was admitted. Radiance's 640 u ring is a `RING` effect in the budget (18 ticks, 640 u: `radiance_ring_frames`, `radiance_ring_radius_u`), not drawn by the combat view.
  - **Effects are drawn from their first tick.** `on_tick` ages the budget first and then spawns this tick's effects, so each is drawn at age 0 and lives its whole lifetime (it used to be aged once before its first draw).
  - **Sparks are tinted by the tier the hit's damage used**, carried in the hit event (`HitKind.tier_of`), not the tier after the tick: the hit that takes Kindling from 7 to 8 deals Ember damage and shows the white spark.
  - **The telegraph sound** plays on the core's `telegraph_cue` event, which is sent exactly 20 ticks before the swing lands (hitstop on the enemy before the cue pushes the telegraph and the cue back together; after the cue the swing is committed and lands on time).
  - **Slow motion starts after the hitstop.** `SimDriver.slow` holds a request made while the player is frozen and starts its ticks on the first tick after the freeze ends. The parry's 0.5x for 6 f follows its 12 f of hitstop and the Charged kill's 0.8x for 8 f follows its 6 f, so both are seen as slow motion on ticks where the world moves; before, they were spent inside the freeze, where nothing moves, and only lengthened it. The simulation is unchanged: this only decides when ticks come (`test_sim_driver_slow_motion.gd`).
- `game/enemies/enemy_view.gd` draws each enemy from a snapshot of the tick (box, state, telegraph progress, white or red cue, attack box, health and poise), interpolated between ticks. It takes the simulation, not the enemy list: a typed `Array[Enemy]` passed to a view leaked the core's scripts at exit in Godot 4.7.
  - The hit flash is `enemy_flash_frames` (2) long, blended to white by the flash setting; at a setting of 0 the body does not flash and an outline colour change (cyan, apart from the white and red cues) shows for the same frames (section 12).
  - A parryable telegraph is a plain raised bar and a straight outline in white; an unparryable one is a saw-toothed bar and a jagged outline in red, so the two differ in shape as well as colour (section 12). The cue stays through the landing frame, the last frame of the parry window (the state is STRIKE then), and the live swing is drawn white or red, with the same outline shapes, through its active frames.
- `game/combat/combat_view.gd` draws combat's world objects: Kindle's cone (relative to the drawn player, so it moves with the interpolated player), Blaze's trails, the kill embers flying home, the blade's heat by Kindling tier, the Charged strike's glow once the hold is long enough, Mend's channel.
- `game/ui/hud.gd`: hearts, the Flame bar (easing, flashing for 12 ticks counting the tick of the gain) and the Kindling tier, top left; the F3 overlay's text starts below it.
- The F3 overlay (`game/debug/`) adds each enemy's box with its state, health, poise and the ticks until its swing lands (`Enemy.ticks_to_landing`, which counts the hitstop that holds the swing back), the live swing (white, or red for unparryable), Kindle's cone, the trails and the kill embers, and a line of hearts, Flame, Kindling, spell, hitstop and knockback. A dead enemy has no hurtbox, so it is drawn as a dimmer outline, labelled dead. The enemy's label is drawn above the highest point of the telegraph's bar.
- The world objects drawn from the simulation (the cone, trails, embers) are game objects, like the player's box; everything decorative (sparks, bursts, smears, Radiance's ring, the screen-space flashes) goes through the VFX budget manager (CLAUDE.md rule 7).


## Alternatives considered

| Option | Why not |
| --- | --- |
| Resolve hits inside the player's step | The player would hit enemies where they were last tick; enemies moving into a strike would be missed or hit a tick late |
| Enemy hits before player hits | A strike that kills an enemy on the tick its attack lands would still let the attack land: trading hits feels unfair to the player |
| A parry window in ticks rather than the player's frames | During the player's own hitstop the ring folds frames together; counting player frames keeps "8 frames" what the player lived through |
| Charged strike on press-and-hold without the press's side 1 | Breaks "attack comes out on frame 3 from a neutral press, every time" |
| Knockback as a velocity the stick overrides at once | 300 u/s is 5 u a tick; the next tick's run acceleration cancels it, and the hit reads as nothing |
| Knockback that locks every action | "No input ever waits for an animation" (CLAUDE.md rule 3) |

## Feel reason

Combat: every hit is resolved where both sides really are, every press made during hitstop survives it, and a hit on the player never takes control away except the stick's sideways push for 12 frames, which any action ends. The rising weight of the chain is in the numbers (2, 2 and 4 f of hitstop, the finisher's shake and launch).

## Consequences

- `tests/replay/combat/` holds a fixture per table row and per rule above; `tests/unit/core/combat/` the resources and the dummy.
- The state hash covers the vitals, the combat state and every enemy; adding combat moves every golden hash (`Simulation.VERSION`).
- The first review's fixes are pinned by a fixture each in `tests/replay/combat/` (each fails on the code before them), and the hash audit counts the enemy's new fields.
- Director questions: the kill ember's 11 Flame; the 12 f knockback; hazards costing a heart; the Charged strike's release buffer; Mend standing still; a spell pressed early in a strike ageing out of its 8 f buffer; a hit during an enemy's last 20 telegraph frames not delaying its swing; the 20 f of invulnerability counted after the hit's hitstop.
