# Engine and content boundary

This project follows the OpenMW/fheroes2 model: independently designed native
systems consume a user's original game data. It is not a line-by-line port, an
iPhone emulator, or a translation of original routines into GDScript. Research
includes inspection of the supplied application; no clean-room claim is made.

## Import once, run native

`ipa_import.gd` identifies the application bundle, validates selected resources,
and builds an isolated, hashed cache. `formats.gd` reads AEM meshes, AEI textures,
language records and delimited catalogues directly in Godot.

`native_import.gd` performs embedded-data reading and staged asset extraction on
one worker at a time. Each worker owns its reader and receives exclusive use of
the archive while running; the main thread polls mutex-protected progress and
joins it before using its result. GPU resources, scene controls, final library
validation and cache activation remain on the main thread. This follows Godot's
[thread ownership and cleanup requirements](https://docs.godotengine.org/en/stable/classes/class_thread.html)
and [resource threading guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
Cancellation is cooperative at data-reader checkpoints and asset boundaries.
Cancelled workers are joined before partial files are removed. A window close
waits for that cleanup, and an overlapping import is rejected. The active cache
is replaced only after all validation; cancellation never overwrites a pilot.

Some original content is embedded in the application rather than separate files.
`native_data.gd` reads named Mach-O constant arrays and narrowly recognized data
initialization patterns. It emits normalized definitions into the user's private
cache and discards the application bytes. It does not execute original code,
emulate CPU state, or emit executable scripts. Unknown layouts fail explicitly.

`library.gd` resolves catalogue, localization and model references. The running
simulation receives definitions and Godot resources through that library. It
does not read machine instructions. Runtime code contains mechanics and native
presentation choices, not copied campaign coordinates, rewards or stock tables.

Mesh registrations reference material resources, which in turn select a texture and
render pass. The importer resolves those declarations into lighting, blend, culling
and order fields. `library.gd` builds cached Godot materials from them; callers do
not guess texture names or pass a glow flag. Additive materials use a small native
shader with full alpha to reproduce ONE/ONE blending. Opaque hulls use native per-vertex directional
lighting without prototype metallic/specular highlights. AEM vertex color arrays are preserved. Unlit materials use them, while lit hulls
retain fixed material lighting, matching the supported profile's disabled color-material
tracking ([OpenGL ES 1.1, sections 2.12.3–4](https://registry.khronos.org/OpenGL/specs/es/1.1/es_full_spec_1.1.pdf)).
The importer reads nine sky light directions, four diffuse color styles and the
separate faction-dependent hangar profile. Sky selection updates cached hull materials.
A full-float mesh attribute preserves source short-normal conversion and magnitude;
the shader applies inverse-transpose model scale and clamps light at each vertex
before texture modulation. Global tone mapping is linear. The supplied build uses
GL_FRONT for material setters, which the GLES specification rejects. Native rendering
therefore uses the standard material defaults; archives declaring FRONT_AND_BACK use
their imported reflectance. Whether old iPhone drivers accepted the invalid face is
still unverified. Native hulls retain authored dimensions; introductory scenes use
the supplied placements and timing with native interpolation. Sky layers retain their
separately imported draw-time overrides. Optional absent meshes remain reported as
missing; they are not replaced with fabricated geometry.

`station_models` contains source station body/light resource pairs, campaign presence
and placement declarations, tilt bounds and rotation period. `presentation/station.gd`
assembles both parts under one rotor without independently resizing either mesh.
Its owner supplies random samples and elapsed time. Missing optional light geometry
is recorded on the node; a missing body fails construction. Later briefing scenes
use these composites through `presentation/briefing_scene.gd`. They are not added to
campaign flight: the inspected source renders them through its cutscene module.

`presentation/station_area.gd` shares imported station-approach geometry between
briefings and native free flight. Location race/image rules select the station
family; source field declarations supply asteroid models, count, extent, rotations
and scale bounds. Briefings retain their source camera and drift clock. Exploration
keeps its field stationary, rotates the station on simulation time and uses the
body mesh for swept player collision through Godot’s
[move_and_collide](https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html#class-physicsbody3d-method-move-and-collide). Its docking envelope comes from the rotating
body's bounds plus the imported player collision radius. That docking interaction
is a native extension, not an imported original mechanic. Asteroids in this area
are still decorative, and station collision currently blocks movement without
assigning guessed damage. Campaign and contract flight retain their own scenery.

The initial executable reader supports the inspected, unencrypted ARM32 build
with its content symbols. Compatibility with differently compiled or stripped
builds requires another verified reader, not checksum exceptions or guessed data.

## Separate meaning from bytes

The importer preserves source references and validates table dimensions, index
bounds and available actor resources. A source resource registration can refer to
an absent optional file; actors required by the supported scenario must resolve.
`market.gd` consumes campaign stock lists and recovered regional/faction rules.
It samples eligible catalogues by occurrence weight rather than copying the original
rejection loops. Stock is stable during a visit and survives save/load.
`loadout.gd` owns equipment instances, mount compatibility and retained resale values.
Parsing a table or importing every dialogue line does not mean a chapter is playable.

`contracts.gd` generates repeatable offer lists from imported category, region,
reward and client definitions. Name files, profession pools, portrait choices and
special clients resolve through supplied data. The native sampler computes the
local-client probability directly instead of repeating the original rejection loop.
Reward arithmetic preserves binary32 truncation and the source's unusual half-step
rounding; asteroid quotes remain per-target rates. Boards have no executable script
or copied mission implementation.

`contract_encounters.gd` builds Revenge and Wanted encounters from their shared
imported declaration: a designated target, tier-dependent escorts, randomized
waypoint and asteroid/fog scenery, and client radio. Destroying escorts cannot
substitute for destroying the designated target. Target and escort hull use their
different source difficulty/rank rules. Generated definitions pass the same
validation as campaign definitions. Imported gun associations select each fighter
family's projectile pool, and freelance gun damage includes the origin quadrant.
Flight builds encounter geometry from its declared field/fog without injecting
the exploration station area. Transport encounters sample three route
points, regional ambusher counts and optional deadlines from their own imported
declarations. Their objective is route completion, independent of enemy casualties.
The native generator chooses ordinary or heavy fighter profiles within the imported
regional quota. Field and fog placement reference a sampled route point; an empty
scenery choice does not create substitute obstacles. Station boards allow accepting these jobs
only after campaign completion or an explicit skip. Unsupported encounter types
remain unavailable. Each visit has a deterministic board; a saved job stores its
station, visit and offer index, then regenerates and validates the native encounter
on reload. Successful settlement returns to the origin and records the imported
payment once. Ordered contract receipts contribute to earned worth separately from
campaign receipts. Defeat and retry grant no payment or campaign progress.

`mission.gd` consumes declarative routes, target groups, objectives and deadlines.
Actor damage, positions, elapsed time and outcomes live in serializable simulation
state rather than scene nodes. `radio.gd` schedules imported text from conditions
and records consumed messages. Reading durations use imported line timing and native
word wrapping against the IPA’s bitmap glyph advances, independent of speedup. A
saved lead-in keeps pending messages hidden across reloads. Older saves without it
retain their current cue with a capped reading timer. `presentation/dialogue.gd`
draws supplied portraits at imported panel coordinates, with scalable desktop text
and original bitmap lettering on mobile. The shared `presentation/panel.gd` uses
source fill/border colors, smooth desktop edges and original mobile corner artwork
for radio and manual briefing pages; long text can extend the panel. Enter or
a direct touch dismisses only the visible cue. Notifications use a separate label.
The import reader resolves character image IDs through resource registrations and
validates atlas glyph bounds. No original drawing or scheduling code is executed.
`tutorial.gd` schedules visual action highlights from imported radio selection links,
intervals and blink timing. Its independent saved timer advances beside the readable
radio clock, once per unpaused frame, regardless of simulation acceleration. It never
activates controls or gates player input. Core action buttons remain visible on desktop
as well as touch screens, so imported instructions always have a visible target.
Schema12 saves migrate by skipping highlights whose radio messages were already
selected; their gameplay and dialogue state remain intact. Current opening saves
require a valid tutorial cursor, elapsed time and blink phase.

All thirteen campaign chapters use these systems. The opening imports sleeping,
unarmed fighter targets, their factory scatter and rank hull, nominal speed metadata,
Christine’s relative placement and route, and separate asteroid/nebula waypoints.
Targets wake through the shared proximity system before the final route point.
Further combat fidelity remains pending. Do not add
placeholder mission rewards, fallback ship catalogues or invented stock lists.

`encounters.gd` independently steers interceptors and escorts using imported motion, activation
bounds, angular firing tolerance, firing distance and gun parameters. Fighter
projectiles follow ship facing: source shoot-error fields are normalized angular
thresholds, not random positional spread. Pursuit and breakaway remain native
controller choices. Turret gimbal aiming is handled separately. Escorts engage nearby enemies and then resume their own route.
Serializable actor state preserves activation, heading, route progress, damage and
shot counters. Mission state supports waypoint placement and per-group hull
overrides without embedding a second copy of the mission data. Native capability
checks keep unsupported later chapters unavailable, including during save loading.

The fourth chapter declaration includes separate player/escort routes, grouped
attacker placement, friendly hull and motion, an asteroid-field reference and
objective-bound dialogue. Compound objectives and selected-ally failure are native
state predicates. Ordinary fighter hull uses the imported rank multiplier and difficulty
adjustment; spawn variation uses the recovered factory bounds.

The fifth chapter adds fixed targets and two wingmates. Source-defined initial
health is separate from maximum hull, including the scripted exceptional health
of one ally. Fixed targets activate near opposing actors and use imported body
offsets and rectangular dimensions at their original model scale. This mission
attaches no turrets and its fixed targets do not fire. A ranged casualty cue fires
when any selected enemy dies. The native objective marker can guide the player
to a dormant encounter's imported target area.

The sixth chapter adds a staged duel. `sequence.gd` consumes imported conditions
and declarative actions, including health thresholds, finished dialogue references,
relative arrivals, target assignments and camera focus. It commits each milestone
once with a saved cursor. The engine implements these mechanics independently;
no original state machine or executable script runs in Godot. JSON validation
checks prior milestones without replaying their health or relocation actions.
The native cinematic camera follows imported offsets; original camera translation
and exact choreography remain approximate. Script-directed shots select only their
assigned character, while neutral scenery can intercept them. Swept collision picks
the first obstruction independently of collider enumeration order.

The seventh chapter adds straight cargo transit, compound cruiser collision boxes
and independent turret mounts. Transit velocity, mount positions, facing, aim
limits, turn rate and gun values are imported. Native gimbal aiming and leading
shots consume these definitions without translating the original turret routine.
A saved camera selection captures the first active actor in an imported range;
later deaths do not change the committed selection. The convoy marker follows
the surviving ships. Timed survival requires at least one remaining cargo ship,
and closing timer-based radio remains eligible after the objective becomes ready.

The eighth chapter introduces wingmates without authored routes. Native formation
following uses their imported player-relative offsets when no enemy is in range.
An explicit imported enemy goal can differ from the visible enemy count. Separate
combat participation keeps disabled cruiser hulls visible without allowing shots,
AI targeting or radar markers to treat them as active combatants. This also corrects
the convoy cruiser. Source gun mounts remain independent combatants. Physical
contact uses the fixed hull's imported boxes independently of combat participation.
Save migration restores
legacy convoy hulls and corrects their kill counters without resetting the mission,
pilot, cargo ships, radio, money or weapons.

`body_contact.gd` sweeps the player point against each original fixed-body box in
relative coordinates, including moving cargo. A hit reflects remaining movement
using the imported forward contribution and contact-damage interval. Sleeping or
combat-disabled bodies stay solid; unfinished fixed wrecks retain collision until
destruction ends. Fighters, mines and turrets have no physical contact volume,
matching their source collision methods. Compound hull gaps remain open.
Native sweeps prevent tunnelling and separate a saved player already inside a
hull; they do not reproduce original frame-dependent point sampling. Heading and
throttle remain under player control. Contact cancels autopilot/time acceleration,
and frozen or paused flight preserves the contact clock. Campaign28/survival10
persist the clock; older snapshots initialize it without replaying damage.

The ninth chapter combines existing transit cargo, routed escorts and compound
objectives. Its failure predicate references four cargo ships and excludes the
escort. The importer preserves a second integer hull adjustment after the factory
calculation. A normalized survivor-based reward rule applies the supplied chapter
reward to the remaining allied count and its imported offset. Settlement uses
that rule before clearing mission state, so partial losses affect payment and
reload cannot grant a second reward. Dormant encounter navigation uses each
surviving actor's position, including groups distributed over several locations.

The tenth chapter reuses native wingmates, fixed bodies, turrets and fighters.
Its allied frigate has three imported collision boxes and stays stationary. The
hostile cruiser remains outside combat while its guns and fighters count toward
the objective. Campaign turret health comes from its factory constant, distinct
from chapter-specific overrides. The event dispatch is checked explicitly; this
chapter does not borrow a later chapter's scripted sequence.

The eleventh chapter introduces a selected-enemy death objective. The commander
uses the hostile fighter factory role and its imported aiming error; escorts retain
their own hull adjustment. Nebula texture, region, volume, sizes and palettes are
read from the supplied content. `nebula.gd` composes native billboard clouds using
a separate deterministic cosmetic generator; combat randomness is unaffected.
Cloud placement is a native composition, not an exact reproduction of the original
sprite implementation or random generator.

The encounter director also supports bounded route phases recovered from source
events. A completed event determines which waypoint interval is active; saves
retain the event cursor and route progress and reject inconsistent combinations.
Sleeping friendly escorts use the imported player-proximity boundary. Radio
conditions can require an entire enemy group to be destroyed, an allied actor
to activate or die, or both an earlier message and an active selected enemy.
The twelfth encounter uses these with nominal speed metadata, route detachment,
heading-relative placement and a directed attack. Fixed midpoint camera positions
are recorded once and survive reloads. Ship models remain visible while their
combat behavior is asleep, so cinematic cameras can show a dormant escort.
The native director advances ten imported milestones and waits for the closing
radio before settlement. Its last event removes the departing commander.
The final campaign encounter follows the pursuit and ends the linear campaign.

`scenery.gd` owns deterministic field placement and persistent destruction. Imported
count, bounds, model, scale range and collision parameters define the field. Normal
shots reduce asteroid durability; missiles and player contact destroy the rock.
Swept contact applies the imported player damage and contact interval. Native
presentation uses the original fragment meshes and six explosion layers. Each
parent has an independent native simulation clock with imported layer durations,
delays and alpha thresholds; completion contributes one billable asteroid. This
avoids the original shared handler's coupling to the number of rendered rocks.
The continuous envelope and independent clocks are deliberate native behavior,
not a claim of exact original frame-by-frame animation. Schema16 preserves old
cleared rocks as finished and retains partial durability.

`actor_destruction.gd` separates live, dying and finished NPC phases. Imported
layer fade thresholds determine completion. `mission.gd` advances the saved clock
before evaluating specific-target objectives; `sequence.gd` uses finished wrecks
for its actor-dead conditions. Radio uses the source base-player HP predicates,
so it does not inherit the additional objective wait. Survival awards kills at
zero hull but only reuses a slot after destruction is finished. A new life receives
a new clock, allowing the previous effect to retain its hull and audio safely.
The renderer follows that simulation clock and reconstructs unfinished wrecks on
load with stable cosmetic variation and elapsed sound cues suppressed. Campaign
save24 and survival snapshot7 retain velocity, body frame, maneuver state, phase and elapsed time.
Older saves without wreck lifecycles preserve casualties as already finished;
save20/snapshot3 retain unfinished phases with zero previously unknown momentum.
Migration never invents kills, rewards or elapsed explosion history. Player death
presentation remains separate from gameplay: its background effect continues behind results.

`encounters.gd` records instantaneous fighter velocity, including transit cargo and
director stops. Wrecks integrate exponential damping analytically from the supplied
fighter retention and nominal animation interval. Movement stops at the final
layer fade threshold, even when a large simulation step crosses that boundary.
This preserves speed retention independently of display frequency; it does not
emulate the original per-frame integer truncation or slow-device timer cadence.
Save velocity limits account for current speed and boost profiles; legacy nominal
velocity remains permitted for wrecks created before the motion migration.
The renderer follows the same-life actor position, so a reused survival slot
cannot teleport an older explosion to the new ship.

`combat.gd` advances serializable projectiles and weapon cooldowns. Catalogue
values supply damage, reload interval, lifetime and speed; embedded collision
extents supply target volumes. Continuous box intersection tests choose the first
impact and support relative target motion. Presentation nodes render the resulting
state. NPC weapon profiles supply team ownership, so shots can hit opposing
actors and neutral geometry without trusting a team value in a save.
Heavy transport ambushers have native pursuit
guidance in `guidance.gd`, with imported acquisition delay, search volume, response,
speed, lifetime and per-actor pool capacity. Acquisition uses opposing identities,
visibility and active/alive state; a committed lock retains its target and last
position across save/load. Native floating-point steering does not claim bit-exact
legacy integer arithmetic. Presentation combines the imported missile body with
its separate additive glow, preserving both resource/material associations and
their shared transform.
Player guidance, trails and multiple firing patterns use the shared native
armament and presentation systems described above.

## Progression and persistence

Campaign, skipped campaign and completed campaign are distinct states. Normal
exploration unlocks only after a supported terminal campaign event. Skipping opens
a separate exploration slot without granting story completion or its rewards.
Finishing a supported scenario pays its imported reward once, advances one chapter
and keeps exploration locked. It waits for closing radio messages before arriving
at the imported destination. A destroyed player cannot complete a mission. The
loader rejects unsupported campaign definitions and inconsistent progression. `progression.gd` records actual campaign payments, including survivor-dependent
rewards, and derives earned worth and rank from imported starting values and growth.
Spending affects cash separately. Each encounter captures its starting rank for
hull and weapon rules; restore validates that rank against reward history before
accepting actor health or shots. One payment can advance at most one rank, with a
strict threshold and a new earned-worth checkpoint after promotion.

Each archive's SHA-256 identity separates its cache and saves. Activation uses a
staged import; save writes keep a previous checkpoint and reject incompatible or
malformed data. Development preview arguments use transient pilots. Source and
binary exports include no imported resources, original executables or saves.

## Verification

The integration test accepts an external IPA, verifies every imported model and
texture, exercises real autopilot and weapon behavior, checks progression gates
and save recovery, and mutates embedded content in memory. Changed source rewards,
coordinates, target counts and starting credits must change the extracted data.
Economy checks cover every imported station, failed-purchase atomicity, fitting,
ship transfers, cargo price dependence and JSON save round trips. Original fixtures
and extracted values are not shipped as runtime fallbacks. Campaign checks cover
actual clearance combat, deadline failure/retry, duplicate reward prevention, radio
ordering and consumption, target damage persistence and old-save migration.
Further checks cover interceptor declarations, changed source difficulty and hull,
radio actor ranges, actual interceptor combat, death/retry and save restoration,
escape deadlines, closing transmissions and automatic destination transitions.
Changed source enemy motion, gun values and rank must affect the native simulation.
Ballistic checks cover flight time, nearest impact, range expiration, moving targets,
step-size consistency and save/reload without resetting weapon cooldowns.
The ten-mission run includes a mid-battle reload during the fifth assault and
reloads at three stages of the sixth duel. It checks complete radio sequences,
imported arrival/rewards and the remaining campaign gate. Source mutations also
change duel hull, surrender message references, arrival and camera offsets, and
distinguish projectile speed from pool capacity. The convoy run restores three checkpoints during real combat and verifies
its timer, cargo survival, turret shots, complete dialogue, destination and reward.
Focused checks cover moving cargo impacts and the reusable compound-body hit
path, all-cargo-loss retry,
committed camera selection and changes to supplied body, movement and aim data.
The cruiser attack completes after the preceding seven missions with a battle
reload, all guns destroyed, its disabled hull intact, full radio and source reward.
Changed source actor counts, placements, health and activation flags change the
imported encounter; unexpected event scripts are rejected.
The ninth mission buys and fits a station weapon using previously earned campaign
credits, plays through both cinematic reloads, and checks convoy survival,
escort progress, all radio and the survivor-dependent payout. Source mutations
change route points, actor selection, health, placement and reward adjustment;
unsupported actor classes are rejected. Total cargo loss fails despite the living
escort, and retry preserves credits and campaign progression.
The tenth battle retains the weapon bought in the preceding mission, restores a
combat checkpoint, eliminates the complete defense group and verifies the
imported arrival and reward. The eleventh continues that earned progression through
its assassination, battle reload, five radio cues and single reward. Objective tests
cover both surviving escorts and killing escorts without the commander. Source
mutations verify target selection, commander aiming and nebula colors.

Use native Godot rendering for visual checks. Controller, touch and other platform
exports also require testing on their target hardware before claiming support.

Save schema15 adds persistent mine phases, fuse/effect elapsed time and the last
source-axis blast delta. Schema14 campaign saves retain all existing actor positions,
hull, kills and rewards: cleared mines migrate as dead; surviving mines become
dormant. No source executable state is persisted.

Faction standing, earned-worth, freelance payment and current briefing records remain required. Older schemas migrate through7:
progress before the upgrade is explicitly marked as an old-preview baseline, since
those versions did not store variable payout history. Existing cash, mission state
and rank are retained; later payments are recorded exactly. New pilots record every
payment from chapter zero. A missing earned-worth ledger in a schema8 or later save is rejected rather
than silently reconstructing past rewards. Transient developer previews explicitly
seed a baseline and are never saved over a player’s pilot. Schema8 saves migrate
with an empty freelance history. Contract records are validated against regenerated
offers, strictly increasing settled visits and the current visit. An active job
must match the current board, encounter seed and earned rank; it cannot reuse a
paid offer. Neither skipping nor completing a contract sets campaign completion.
Schema9 saves migrate with no active briefing. A saved page is accepted only for a
valid source chapter/page in a docked campaign session without an active mission.

`presentation/briefing.gd` renders source-defined pages separately from flight radio.
The importer reads narration boundaries, portrait alternation, page text tables,
panel coordinates, footer labels and normal/pressed atlas images. Native wrapping
uses the supplied font. Pages advance only on deliberate input release; held-key
repeat and emulated duplicate mouse events do not consume additional pages. The
final page starts the mission; Back on the first page returns to the station.
Skipping the conversation uses a separate confirmation and does not skip campaign
progress.

`briefing_scene` imports each chapter's scene mode, location-versus-campaign station
ownership, race/image selection rules, camera framing, station placement override
and asteroid field drift. The native scene supplies original sky layers and paired
station meshes while the separate page control waits for confirmation. Back/Next
keep the scene alive; leaving or starting the mission releases it and its camera.
The scene clock never updates the pilot, radio or mission state.

Zero-based chapters 1–12 use this scene composition. Chapter 0 uses OpeningScene
and `briefing_scene.opening`: imported page transitions, camera/actor positions,
pan/easing parameters, approach/braking values and fade duration. Its native
OpeningChoreography solves motion over elapsed time. Only a new highest page
advances the shot; Back does not rewind it. During fades the dialogue/footer are
hidden and input cannot acknowledge the next page. The exterior is retired when
HangarScene takes over, using the pilot ship and supplied stock. Reload constructs
the shot appropriate to the saved page without replaying earlier text.

Random placement/tilt use a stable native presentation seed; the original prior
global random sequence is not reconstructed. Native continuous motion replaces
source per-frame integer rounding, and cosmetic animation restarts on reload.
Lighting and flares use the existing supplied declarations. Frame-exact camera
lag and cinematic burner pulse timing remain fidelity limits.

Old opening saves are validated against their historical actor shape after adding
missing destruction defaults to a copy. The current encounter then retains saved
positions, damage and kills, introduces its companion, and marks already destroyed
actors dead. This keeps validation ordered correctly when a save predates several
later actor-state schemas; migration does not replay explosions or award kills.

`briefing_ui.audio` recovers the dialogue-to-sound offset and original navigation
cue IDs. It also holds source title/station music IDs and the alien-race selection.
Main restores that music context for direct briefing resumes. BriefingAudio owns
separate page speech and transient navigation players: changing pages replaces
speech, leaving clears it immediately, and a navigation cue can finish across a
screen transition. Suspension pauses speech without restarting or acknowledging
its page. Re-presenting the same page does not replay its sound.

The reference iPhone sound bank registers IDs 0–31; every briefing speech ID is
outside that bank. The original sound lookup treats those IDs as silent, so the
remake does too. It does not synthesize voices or assume filenames for them.
Compatible archives with registered page sounds use those supplied clips and gains.
Audio completion never advances a page. Music keeps the existing remake volume
setting; source sound-effect gains are preserved.

The final encounter reader also recovers the alternate allied capital hull and
turret mounts, the commander's own weapon balance, the message-driven objective
and the terminal campaign announcement. The full battle uses these declarations directly. Its native director supports the
imported dialogue milestones, temporary vulnerability and freeze flags, reversible
commander suspension, one-time allied sleep, and a persistent camera hold. A parsed
ending marker alone cannot complete a pilot's campaign: settlement also requires
the objective, every director milestone and the closing radio queue. The final
reward receipt, chapter advance and completion state are committed together. Saved
completion requires the source terminal chapter and an actual final reward receipt.

Control capture and explicit movement freeze are separate: the final conversation
can leave the ship moving while its camera stays fixed. Saved camera anchors and
sleep transitions are validated against committed milestones. Earlier encounter
declarations retain their existing native lock behavior. The original executable
is used only to recover supported data declarations during import.

Some supplied turret entries refer to an unregistered mesh. Their imported
presentation flag preserves the native combat position and weapon without
substituting a different model. This exception applies to turret roles; ships
still require a resolved model resource.

Schema11 saves add source-defined throttle and boost state. Schema12 introduces
source opening encounters. An old opening formation is validated before migration;
its positions, destroyed targets, damage and radio progress survive. The companion
and asteroid field are generated from the current imported definition. Current
saves require their complete actor and scenery state; malformed old damage is
rejected rather than repaired. Original motion and scenario declarations remain
imported data, while steering, collision handling and autopilot are native systems.

Fighter direction correction uses `fighter_steering` data recovered from its actual
update consumer. The generic KIPlayer rotation-speed field remains source metadata;
it no longer controls native fighter turning. Imported normal/enhanced gains use
milliseconds and normalized fixed-point vector units. Actor and campaign selectors
choose the appropriate gain, and the source near-alignment threshold ends small
corrections. Native spherical integration keeps fixed-target response independent
of update subdivision without copying the original matrix/integer implementation.
Exactly opposed vectors require a lateral direction to establish a turning plane.
Overlapping combat targets cannot stop a fighter's forward travel. Saved heading
and velocity preserve continuation; no new save fields are needed for turning.
`fighter_evasion.gd` holds imported lateral directions while a target remains in
its source axis-aligned avoidance box. Constructor-specific extents apply to
heavy/special fighters. Repeated source choices preserve their original weights.
A per-actor decision counter and encounter seed keep choices independent of visual
randomness and stable across saves. Route following suspends the maneuver without
forgetting its direction; leaving the target box or starting a new life clears it.
Aligned maneuvers can fire along the hull direction using source range/aim limits.
Save21/survival4 lack lateral decisions: migration clears the obsolete reversal
flag while preserving pose and momentum. Current saves validate active/held
choices, counters and unused survival reserves. Body up is carried through native
turns and saved. Rotation-lock dispatch, target selection
cadence and formation handling remain fidelity work.

FighterMotion integrates current speed independently of the generic base-speed
metadata. Imported constants define initial/cruise speed, boost cap, acceleration,
braking, decision interval, accumulated damage threshold and duration refresh.
The source random decision refreshes duration; a failed refresh retains the prior
duration and still accelerates. A previously zero duration gets one nominal source
update of acceleration. Native continuous timelines avoid frame-size overshoot.
Special and heavy fighters use imported proximity boxes, multiplicative gains and
distant speed floors converted through the source animation interval. Native
coordinate-range failures are reported; no inferred gameplay speed cap is added.

Campaign23/survival6 save current speed, phase, timers, observed hull and an
independent decision counter. Sleeping actors age their decision timer without
moving. Modal pauses freeze both clocks and translation. Respawns clear speed and
damage state while preserving the eligible fighter's decision stream. Older saves
start fresh boost history at the source initial speed, preserving pose, damage,
rewards and existing wreck momentum. Generic source setSpeed directives remain
metadata because the fighter translation consumer reads a different current-speed
field. Transit objects keep their own declared velocity. Native targeting/replay
prediction uses recorded velocity rather than reconstructing it from nominal speed.
FighterImpact handles the separate source-flagged rocket response described below.

NPC gun declarations include projectile capacities. Ordinary hostile fighters and
friendly fighters each share their level-owned Gun pool; scripted fighter weapons
and turrets have individually allocated pools. The reader binds capacity to the
Gun constructor's allocation parameter and retains shared identity only for reused
guns. Cooldowns belong to each ship's slot, not to the shared projectile pool.
A saturated pool consumes that shooter's firing interval without emitting another
projectile. Hits and expiry release slots. Old saves retain any excess live shots
from earlier previews; emissions resume only after the pool drains below capacity.
No save layout changes are required because occupancy is derived from projectiles.

Time acceleration and autopilot are native extensions, so their threat test is
native code as well. It asks whether any live projectile belongs to a hostile
weapon, and weapon profiles are rebuilt from the mission on every request. The
test now reads that table once instead of once per projectile, and skips it
entirely when a cinematic, a hostile actor or recent damage already answers, or
when no projectile is live. A hostile actor short-circuits the scan, so the cost
only ever appeared with none present: firing into empty space with a fast gun.
Behaviour is unchanged; only the number of rebuilds is. Projectile visuals read
the same table once per synchronization rather than once per newly created bolt.

The weapon table itself is assembled per request, and flight asks for it several
times per simulation substep. Its player half derives only from the catalogue and
the mission's target list, and every consumer reads it, so it is built once per
distinct target list and kept on the library beside the mesh and texture caches.
Actor guns are still assembled per request, because the directed-fire targets in
them are rewritten there. Nothing is cached across a reopened content directory.

Ballistic sweeps read each target's identity, side and swept volume once per
advance rather than once per projectile tested against it, and a shooter's own
side once per projectile rather than once per target. An asteroid field supplies
eighty targets, so that inner product dominated a sustained burst. The geometry
of the sweep, the nearest-impact rule and directed fire are unchanged.


## Distant flight backgrounds

`NativeData.sky_presentation` recovers sky mesh/texture associations, variant counts,
style tints, draw blends, seeded selection parameters and the campaign override table.
Texture registration recognizes identifiers held in different registers, including the
white sun atlas. Every referenced mesh and texture is checked before activation.

`presentation/backdrop.gd` builds four original layers: stars, distant nebula, planet
layout and sun. Station image data chooses the planet layout; imported campaign
associations override it where required. A separate standard LCG with imported
parameters selects repeatable sun/nebula variants without consuming encounter randomness.
These are rendering declarations, not executable game routines.

The native shader removes camera translation and projects these layers to far depth.
Source layer order and alpha/additive blending are preserved; foreground geometry still
occludes the sky. This uses Godot's documented `CLIP_SPACE_FAR` value for each renderer:
[Godot spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).
The gallery checks all nine layouts, large camera translation, rotation and opaque
foreground visibility. Lens flares use the separate imported sprite presentation.
Campaign station models are drawn by the cutscene module; MGame's flight renderer
does not submit them. The legacy SpaceObject sprite system likewise has no active
drawing consumer in this iPhone build. Native free exploration adapts the station
approach scene as described below. Source light direction
is handled by the material lighting system described above.

Flight presentation attaches original burner meshes beneath each hull using separate
imported player/NPC attachment tables. Every nozzle retains its own mesh variant,
position and dimensions; hull display scaling applies to its attachments too.
HUD artwork and margins are recovered from bounded image/layout declarations.
Native Godot controls manage action touches independently by finger, while original
atlas regions and bitmap glyphs draw the flight composition. Imported code is
never used as the runtime UI or effects implementation.

The modern variable-throttle exhaust scales player plumes against imported cruise
speed using forward travel per simulation step, including collision clipping.
Lateral displacement cannot power rear nozzles. Imported base transforms
remain immutable, so slowing, stopping, boosting and resuming cannot accumulate
scale drift or affect another ship's shared mesh/material.


`map_ui` contains source image associations, destination preview selectors, faction
label references and the nested galaxy coordinate dimensions. Quadrant, system
and station names are read from the supplied text tables. Station-info presentation
masks technology and trade for unvisited destinations. Source image indices and
race selectors are resolved at import time; the runtime never guesses preview
textures from their atlas order. `map_icons` separately recovers the small station symbols and the planet-icon
cycle used by the source map. `presentation/galaxy_map.gd` implements native
quadrant/system/destination navigation over those tables, including keyboard,
touch cancellation, Back behavior and the current-position marker. Search results
reveal their source system in the graphical map. `map_ui.layout` imports chart bounds,
background origins, annotation labels/units and colors. MapMenu uses the original
full-screen framing art and footer buttons, with a native search drawer accessible
by touch, F or controller X. Backgrounds retain their original scale. Native grid
navigation selects cell centres; source cursor animation is not reproduced.

`simulation/travel.gd` calculates native transfer quotes from imported coordinates,
map projection dimensions, quadrant weights, price factors and distance precision.
The source numeric precision is expressed as an analytic grid quantizer; the
runtime does not execute or translate the original square-root routine. Prices
use the original projection extent regardless of the player's display size.
Session travel validates eligibility and available credits before arrival and
payment. Flight cost and faction bribe are shown separately. Unique station visits
drive the full-exploration fare waiver; duplicate saved visits are rejected.

Faction limits, completed-job changes, default campaign client race and bribe
decay are imported declarations. Successful settlement updates standing once,
using the actual freelance client's race when applicable. Schema13 saves migrate
by replaying their validated campaign and ordered freelance receipts through the
native faction rules. Unrecorded old-preview history and skipped chapters do not
invent standing. Encounter affiliation follows each mission's imported actor and
client associations; standing does not dynamically reassign combat teams.


`flight_ui.radar` records original frame/marker/aiming atlas associations, proximity
extent, actor exclusions, health-bar dimensions/colors and hit-feedback duration.
The importer recognizes the additional bounded temporary atlas records used by
these images. Unsupported image creation or timing declarations fail validation.
Godot projects markers from native actor positions, selects source near/far/off-screen
artwork and clips off-screen bearings to the viewport. The original side-frame
corner bands remain at their source proportions while plain spans stretch for
modern aspect ratios. Nearby health bars read actual imported actor hull limits.
Player projectile impacts start the imported aiming-ring timer; pause preserves it.
The optional predictive reticle uses imported distance steps and selected weapon
speed. Health bars include the source translucent lower edge, with separate enemy
and friendly colors. This is a native composition; projection uses Godot camera
coordinates rather than the original fixed-point projection. Original projection
smoothing and remaining alternate-affiliation cases have not been verified.

Touch-only flight buttons and joystick drawing follow the same explicit touch
setting as drag steering and the throttle toolbar. Desktop defaults to hidden;
mobile defaults to enabled. Hidden controls cannot claim fingers or consume
emulated mouse clicks. Status, frame and target markers remain. Pause, Time, Autopilot and Dock
buttons follow the same touch preference; their keyboard/controller actions remain.


Mine behavior is an independent native state machine in `simulation/mines.gd`.
A bounded import reader recovers the static-actor association, proximity extent,
fuse, damage, opening meshes and two explosion-layer envelopes. Dormant hull
restoration prevents long-range fire from bypassing arming. Gun destruction and
fuse detonation have separate phases; target-prefix objectives wait for the effect's
completion, while casualty radio uses zero hull. The encounter director runs on its normal
schedule; a mine update cannot consume an additional cinematic milestone.

The supported source uses asymmetric upper-axis blast bounds and, after arming,
selects the first opponent using the last active opponent's delta. The reader
recognizes those semantics explicitly and native compatibility preserves them.
This is not a radial damage implementation. Native animation uses continuous
cosine easing over imported durations rather than the old frame-dependent fixed
point accumulator. Warning rotation and separate arming, shot and explosion sounds
use imported declarations; exact legacy frame timing is not reproduced. Original
mesh sizes and per-instance materials are retained.


Freelance minefield declarations come from the contract factory's temporary spawn
route, randomized total count, leading static mines and single final defender.
The player receives no route or deadline from that branch. The native generator
uses imported center bounds and separate static/fighter scatter. Target-prefix
completion waits for every mine's lifecycle to reach dead; the defender remains
independent. Existing contract references, deterministic encounter regeneration,
radio, retry and fixed-payment receipts are shared with other contract families.
This adds no save schema: older builds did not support accepting this job family.


Asteroid freelance contracts recover a temporary field center, difficulty-scaled
awake pirates and a survival objective. The source timer is a success duration,
not a failure deadline; neither empty pirate groups nor clearing every rock ends
it early. Quotes remain rates. Settlement multiplies the rate by completed parent
destructions and stores bounded units in the receipt; fragments and last-second
pending effects are not billable. The board reference still identifies the original
quote, preserving deterministic regeneration and duplicate-payment checks.


Escort contracts import a temporary three-point route for sleeping attackers and
optional asteroid or nebula scenery. The route is discarded as a navigation
objective. Five fixed-body transports share a player-relative jittered formation,
using faction-selected meshes and one or five imported collision boxes. Their
health follows source rank, quadrant and difficulty arithmetic; movement uses the
fixed-body speed. The native success condition is strict elapsed-time survival,
with immediate failure when the whole convoy is lost. Payment is the fixed quote,
independent of the number of survivors. Nebula definitions support an explicit
center as well as an exclusive route-waypoint reference, preserving campaign clouds
while allowing temporary-route scenery. Existing native combat, save validation,
radio and receipt handling also apply to escorts.


Intercept contracts recover a cargo prefix and a separate guard count from the
freelance factory. Cargo uses the opposing faction's fixed-body model and collision
box, overridden random placement and a stopped-movement flag. Guards use native
fighter combat and imported factory health, weapons and full scatter. The source
navigation point locates optional asteroid/fog scenery and an optional wingman;
completion depends exclusively on the initial enemy prefix. The HUD prioritizes
that prefix over waypoint guidance. Fixed receipts and damage snapshots use the
existing native contract persistence path. Import readers validate the target/guard
array boundary as well as the stopped-body flag and prefix objective consumers.


Capture contracts recover the two route volumes, faction capital/turret association,
guard count, optional scenery/wingman, and turret-prefix completion condition.
Native generation samples the capital's factory scatter once, adds each source
mount to that same center, and preserves enemy ordering: turrets, fighters, inactive
capital. The capital keeps its original compound hull and full model scale but
cannot be damaged. Guards can survive completion, and route traversal is optional.
Turret health follows the freelance base + base*quadrant + rank*coefficient rule,
separately from campaign health. The Terran gun shares the common enemy pool;
the alien gun imports its distinct damage, cadence, pool and ObjectGun model.
Absent Terran turret art leaves functional, marked hardpoints without a fabricated
mesh. Native turret tracking/projectiles and existing contract persistence handle
combat, partial damage, replayed definitions, receipts and retry. Import schema63
adds these declarations; save schema16 remains compatible.


### Cargo recovery

Import schema64 adds bounded recovery declarations: catalogue selection, quantity
and entry-count distributions, unique item identity, capacity reduction, campaign
exclusions, and original labels, atlas bindings, row dimensions and colors. The
source measures rows using image528; the native view draws their fill and border
separately and uses the shared original window frame and bitmap font.

`simulation/recovery.gd` generates deterministic native loot. Distinct item sampling
has the original distribution; its random sequence is independent of the legacy
engine. Quantities are reduced in ordered rounds to fit space remaining after both
cargo and unmounted equipment. Campaign chapters zero and one exclude generation;
chapter two guarantees recovery. Other completed jobs use their enemy-kill count
to select optional or guaranteed recovery. Survival gameplay uses its own score
and upgrade progression and remains excluded from campaign cargo recovery.

Session settlement waits for the closing radio, adds recovered cargo alongside
mission rewards, and persists a display receipt. Save schema17 migrates schema16
without retroactive loot. Reload and acknowledgement never add cargo again.
`presentation/recovery.gd` shows the result over the continuing cosmetic departure, or the ship
view when resuming a docked save. Confirmation supports keyboard, controller, mouse,
touch and the native Back action. Dock UI resumes after the receipt is acknowledged.


### Survival mode

Import schema65 registers the complete survival declaration: score/population rules,
player setup, mounted armament, fighter motion, local record rules, menu, HUD and
choice-dialog presentation. `content/survival_content.gd` validates gameplay through
the runtime validators and checks every required text, atlas region and layout
before Library accepts the cache. Older caches require reimport; campaign saves
remain compatible. No original application bytes enter the cache.

`simulation/survival.gd` is an independent score/combo and reinforcement director.
Source tables supply archetypes, weapons, healing, upgrades and population timing.
`survival_session.gd` owns a separate loadout, hull, actor pool and weapon history.
Clearing the current enemies does not finish its endless objective. Kills award
score and healing once; reinforcement stages reuse or replace source profiles.
Unused slots retain their declared reserved stats until a new archetype replaces
that profile. Each new run advances the source starting-ship cycle.

Each enemy and player muzzle has its own firing origin, cooldown and projectile
pool. The initial paired laser uses the catalogue damage divided by its source
mount divisor; the missile uses the survival damage override. Native projectile
profiles bind the original body, optional glow and guidance declarations. Player
muzzles fire together and rotate with the ship. Extra player profile identities
occupy disjoint catalogue-size ranges; campaign weapon identities are unchanged.
Promotions update both player laser profiles without changing shared equipment.
Launched velocities remain intact, while collision damage and appearance follow
the promoted gun, matching the supplied gun replacement behavior.

Survival snapshot2 stores changing actor/director/combat state, not derived profiles.
Loading rebuilds mounts, projectile limits and upgrades from imported declarations
before validating a detached candidate. Old private snapshot1 files are rejected
because projectile identities predate multiple player muzzles. No public survival
save format was released before this version. Campaign save17 is unchanged.

`arcade_profile.gd` holds a source-defined local leaderboard and strict score order:
ties follow earlier entries. Profile2 also retains accumulated qualifying points
when a later score displaces an older row. Rank titles and thresholds are imported.
Run identities prevent duplicate scores; pending runs and ship rotation persist.
Private profile1 files are rejected because retained rows cannot reconstruct lost
accumulated points. Neither rejection resets campaign or exploration saves.

`survival_archive.gd` commits the profile, optional snapshot and optional result
receipt in one content-specific `survival-state.json`. Starting, abandoning,
recording a defeated run and acknowledging its result persist before changing the
coordinator. A completed score removes the run in the same atomic commit. Failed
writes preserve the live run, name draft or receipt so the player can retry.
Loads validate a detached coordinator and fall back to the prior valid checkpoint;
subsequent writes preserve that validated backup rather than a corrupt main file.

Main connects title entry, Info/Highscore, Start/resume, pause, autosave, defeat,
name submission and acknowledgement through this archive. A recovered result is
shown before a new run can start. Explicit abandonment grants no score. Survival
has no station recovery, docking or campaign objective controls.

The Info/Highscore views, legend, previews, score bar, rank text, result window and
name-entry form use imported artwork, layout and bitmap glyphs. Native text input
supports caret/selection and blocks duplicate submissions. The owner controls
pause and commits the result. Original choice-dialog strips stretch to accommodate
long localized messages while keeping confirmation visible.

The survival HUD reads score/time placement, combo captions, unlock notices and
strength-specific near/far/off-screen markers. Feedback follows simulation time,
survives live HUD rebuilds, and suppresses old notices after loading. The source
score threshold gates missile firing; the visible touch button dims until available. Per-run seeded sky
selection uses the supplied sky/style/cloud counts and recreates the same scene
on resume without advancing the combat random stream. The source SpaceObject sun
association belongs to the remaining lens-flare effect, not obstacle scenery.

Focused checks cover source mutations, declaration validation, mounted combat,
snapshots, interrupted writes, UI input and the installed title-to-result flow.
Missile trails, lens flares and other weapon/cinematic effects remain fidelity work.


Directional HUD damage feedback is a native presentation object owned by Flight.
The importer recovers sprite bindings, flips, margins, fade durations and semantic
front/rear regions from the supplied declarations. Combat impact events include
the direction toward the incoming projectile; damage accounting remains in Flight.
Camera rotation determines the indicated side without camera-position parallax.
Each edge has an independent simulation-time fade. Undirected collision damage
uses a general cue. Visual timers are transient; saving combat state does not
serialize or replay already-presented hit flashes. Desktop and touch HUDs share
the same original artwork and input behavior.


ExplorationArea keeps the native station-approach layout deterministic and saves
asteroid damage separately for each visited station. Geometry, health, collision
rules and destruction artwork come from the imported briefing field declaration,
which already contains the shared Asteroid/AsteroidField parameters. StationArea
uses the same sampling for intact briefing visuals and saved exploration visuals.
Flight routes field collisions and projectile hits through the shared Scenery
simulation while campaign/contract state remains owned by its mission. Survival
has no exploration obstacles. Campaign save19 lazily initializes fields for older
save18 pilots; it preserves existing flight/combat state without inventing previous
asteroid damage. Restore validates immutable geometry and rejects unvisited or
premature campaign exploration records before changing the live pilot.


NpcExhaust owns a cosmetic envelope on each original fighter hull. Import-time
readers recover the NPC boost threshold, two expansion stages, release rate,
width/length factors, minimum dimensions and sine amplitude/rates. The native
controller changes scale on existing nozzle meshes and leaves source mounts,
textures and colors intact. Flight advances it with simulation time and actual
current speed. Wreck controllers remain with their original hull and use decaying
velocity; a survival replacement owns a new controller. Pause freezes the effect.
Source player burner modes remain separate from this NPC consumer. Presentation
phase and envelope restart on reload; saved fighter speed/gameplay does not.


FighterFrame preserves the ship's up direction while constructing its next native
orthonormal frame. The reader verifies the source carried-up/cross-product consumer.
A quaternion handles the singular large-turn case without snapping to world-up.
Evasion directions, weapon mounts/aiming, original hull/nozzles and relative
cinematic cameras use the same frame. Campaign24/survival7 add saved up vectors;
legacy migration reconstructs the previously displayed orientation. Restore rejects
invalid frames before changing live state. Wrecks retain world bank on reparenting.

Scripted HP changes have separate current and maximum semantics. The imported
setHitpoints consumer raises maximum hull when needed and does not lower it when
current hull is subsequently reduced. Sequence.maximum_hull derives that maximum
from executed health actions for damage-triggered fighter boost; current-health
validation remains separate. HUD leading uses actual recorded actor velocity.


FighterImpact is an independent reaction timeline over imported effect associations,
duration and angular/displacement scales. The player weapon factory's Sparks
assignment determines eligibility, independently of catalogue category or projectile
renderer. Shared NPC gun declarations retain a boolean effect flag after their
shared-pool identity is removed for an independently owned gun. Ballistic impact
events carry the incoming velocity; the original nominal frame interval and vector
unit convert it to a small drift factor. Modern rendering frequency does not scale
the knockback. Native local pitch rotates the saved body frame while current-speed
integration supplies drift distance. Normal movement resumes with any remaining
part of a large step. Repeated hits change drift without restarting the timer.

The imported heavy actor bypasses the source pitch/timer branch while retaining
its firing latch; the native engine preserves that separate behavior, including
independent turrets. It does not invent a universal recovery timeout. Revival
clears the response. NPC booster visuals continue to use the separate source
current-speed field; their source consumer does not use the zero-valued speed
getter during an impact. Player damage feedback and flight control remain separate.

Campaign25/survival8 persist active response, elapsed time and drift vector. Older
saves gain an idle response without inventing earlier hits or discarding ongoing
projectiles. Legacy player projectile identities keep their previous no-reaction
behavior. Validation rejects malformed reaction states before changing live play,
and survival reserve slots cannot acquire an unearned active response. Original
hulls/nozzles, wrecks and cinematic offsets use the same saved rotated body frame.


FighterTargeting uses a stable pre-movement opponent roster, ordered as declared
by the source team lists, with the pilot first for enemies. Imported acquisition
extents, selection interval, probabilities and retry count drive an independent
native decision system. Live random selections remain held outside the acquisition
box until the next decision or target deactivation. Failed acquisition returns to
a viable route or the first roster slot; weapon range does not select escort
opponents. Scripted target directives remain authoritative; turrets keep their
separate targeting system. Free-contract reconstruction carries the generated
source mission type, so campaign level exceptions do not leak into freelance play.

Campaign26/survival9 preserve target ID, hold, elapsed time and independent random
counter. Migration starts fresh decisions without altering existing flight state.
Revival clears selection and retains the native random counter. JSON validation
uses numeric value comparisons, including unused survival slots. Random streams
are native and deterministic; continuous timing preserves fractional overshoot
rather than reproducing the original integer update/discard boundary. The source
rotation locks identified so far apply to decorative menu/station CutScene3/4
traffic, not ordinary playable ships. MenuScene owns that decorative motion.


Ally activation uses a separate imported extent, verified against the pilot-position
and state-dispatch consumers. Enemy-less route-less wingmates point directly toward
the pilot inside that box; spawn offsets are not continuing formation slots.
Sleeping allies use the same source extent, while explicit sequence suspension
retains priority. Mission placement requires declared scatter, points, waypoints or
player-relative placement for multiple ships; a singleton can use its source center.
No fabricated spacing or fixed vertical/rear shift is added when those declarations
are absent. Unsupported multi-ship placement is rejected rather than invented.


MenuTraffic imports decorative scene declarations and samples an independent ship
roster. MenuScene renders it behind the title, dock, market, contracts, map and
non-flight options. Supplied routes, station-race hull associations, conditional
density, initial placement, camera settings, rotation locks and trail styles remain
data. Route clones reset their cursors independently of random spawn positions.
A fixed native presentation tick makes motion and trail history independent of
redraws; loops advance the route cursor without teleporting. Vertical heading locks
preserve altitude. Friendly decorative ships use imported initial current speed.
The scene never updates pilot, mission, combat, economy or save state.

The fixed camera looks at the final moving ship, including the current pilot hull
when a campaign mission is active. Planet docks use imported sky/planet meshes;
orbital docks add the location's original station body/light composite at the
supplied placement and scale. The unused legacy SpaceObject sprite is not
duplicated over the iPhone sky geometry. Original nozzles use the existing burner
presentation; local traffic uses the shared ribbon renderer with imported friendly
trail style, history capacity and cadence. Scene disposal stops its clock and
hides its independent flare layer immediately. Station submenus and cinematic
scenes use their separate native presenters described below.


`title_ui` imports the title menu's artwork bindings, localization associations,
button placement tables, decorative positions and fade declarations. TitleMenu
uses original atlas textures and BitmapFont with native focusable Buttons. The
five-row root leads to native campaign/skip/survival and load/save choices; Game
files replaces the obsolete promotional link. Engine-specific help uses the same
frame and bitmap font. Invalid atlas bindings fail content validation before
rendering. A guarded split resource initializer supports the declaration spanning
a literal pool without treating the pool as instructions. Decoration row spacing
comes from the tallest of its supplied frames; indicator visibility is static.

A centered480×320 canvas preserves the original menu proportions across viewport
sizes. Submenu navigation retains the ambient scene and never mutates progress.
Unavailable saves and preview-only save actions are disabled. Errors remain
readable inside the title frame. Leaving title disposes its widgets immediately.
Native menu input adds controller A/B, D-pad and left-stick actions while keeping
keyboard defaults; touchscreen input uses the existing touch-to-mouse emulation.
The initial IPA chooser remains native because no source artwork exists yet.

`options_ui` imports Controls/Audio/Display labels, original checkbox and slider
artwork, rail colors and the volume scale. OptionsMenu uses those declarations
with focusable native buttons and sliders. Native sensitivity, aim assistance,
linked firing and touch visibility live within the corresponding sections.
Rows accommodate the taller supplied slider artwork and keep the footer clear.
Back returns through the section hierarchy to the title, dock or paused flight.
Settings apply without advancing simulation or changing pilot state.

AudioSettings routes music and effects through separate buses. Their saved gains
multiply existing per-player levels, preserving relative sound volumes; zero mutes
only the selected bus. Speech, navigation, weapons, impacts and explosions use the
effects bus. New gains default to unity to preserve the previous native mix.
The pre-import settings screen uses native widgets until supplied art is available.

`pause_ui` imports the original four pause labels, row count and spacing, with
guards for the menu-entry and resume consumers. PauseMenu shares TitleMenu artwork
and adds native Save pilot; Survival exposes a separate confirmed Abandon run.
Help and Options retain paused flight. Save notices and failures reuse ChoiceWindow,
which gates underlying actions until acknowledged. Main menu saves successfully
before disposing flight. Keyboard/controller Back first closes a notice or Help,
then resumes at the root; controller Start follows the same hierarchy.


`station_ui` imports the station home tab roles, localized labels, shared frame,
row/preview/credit artwork, geometry and campaign/shop availability rules.
StationMenu uses the supplied atlas and font with native focusable buttons.
Campaign Missions/Map tabs remain disabled; Hangar, briefing and exploration
navigation dispatch to their existing native systems. Engine options use an
original-art button overlay. Hangar and Job Board have their own presentation
modules described below.

The nested Status declaration imports its five row labels, protagonist/name,
portrait and loyalty-gauge associations, placement and reputation thresholds.
PilotStatistics records real elapsed session time independently of simulation
speedup; title/import, pause/options, focus loss and transient previews are excluded.
Briefing, dock, market, mission board, map, recovery and active flight count.
Mission kills commit once with successful arrival, and completed mission counts
come from campaign progress plus freelance receipts. Reputation uses the imported
thresholds, while loyalty uses the existing faction rating. Survival retains its
separate score and time records.

Campaign save schema27 preserves these counters. Older saves start an explicitly
partial time/kill history; a mission elapsed timer cannot reconstruct lifetime
play time. The Status screen marks partial statistics and explains the missing
history. Skipping the campaign neither awards nor resets these counters.


`hangar_ui` imports Ship/Cargo/Shop roles, catalogue icon/preview tables,
localized description associations and EquipmentList property labels. HangarCatalogue
projects native inventory and station offers without copying catalogue records or
prices into the UI. Sorting retains transaction indices. HangarMenu supplies native
focus, touch scrolling, actions and an Info view inside original atlas artwork.
Previews preserve aspect ratio within the space left by title, price and actions.

The nested quantity declaration imports SellCargoWindow art, labels, amount bounds
and layout associations. CargoSale starts with the current stack and shows a price
total using additional repeats of the original middle strip. The modal owns input
until confirmation or cancellation. Session validates the selected amount against
current cargo before applying one stock/credit/inventory transaction; Main saves
once. Old one-unit callers retain their behavior through the optional amount.
ShipExchange now uses imported summary rows, localization and Layout box colors
with the original font/footer. It shows the native policy of keeping equipment
and cargo. Session quotes actual offer/ship/balance/inventory and transfer state;
confirmation compares a fresh quote before using the same purchase rules. A stale
or altered quote cannot choose its own price, transfer or stock identity. The
legacy footer-measure resource is retained as unresolved metadata; native placement
uses the supplied footer buttons. Its tiny header-image binding remains unresolved.

`hangar_ui.scene` supplies the race-to-interior/light associations, shadow meshes,
parking positions, ship orientation and entrance camera constants. HangarScene
loads authored dimensions and uses the existing Hangar lighting profile. Imported
meshes and placements store reflected Z, which is invisible wherever a camera only
tracks a target but reverses screen-right for an imported camera basis. This is the
only scene that adopts a supplied camera orientation, so its content is presented
on a stage in supplied axes and the camera reads those axes directly. The recovered
right column is then the on-screen right axis, matching the original view. It receives
only the current ship and market snapshot; repeated stock quantities occupy separate
supplied positions. Unsupported overflow is reported without replacing the previous
display. Purchase refresh builds replacement hulls atomically, preserving the camera
and selection. The scene never creates offers, advances gameplay or saves inventory.
The native half-cosine entrance converts supplied angle/time units into seconds;
source fixed-point rounding and its initial-frame delta clamp are not reproduced.
After the entrance, HangarDrift samples each axis independently from imported
asymmetric ranges and endpoint thresholds. Analytic elapsed-time sampling keeps
paths independent of rendering frequency. Its cosmetic random generators never
consume gameplay randomness. The follow view targets the actual parked player hull
and uses its up axis. The supplied constructor does not establish initial drift
direction flags; native presentation selects reproducible allowed directions.
Equipment fitting uses the existing catalogue controls. Original initialization
enters the Ship catalogue, so the legacy empty-overview branch is not an entry
screen. OpeningScene also reuses this interior for the briefing's hangar transition.
`hangar_ui.hints` imports the introduction and Ship/Cargo/Shop text associations,
their first-use tab consumers and acknowledgement sound. HangarMenu shows the
shared original ChoiceWindow with exclusive input, then restores the catalogue.
Acknowledging the introduction shows the unread current-tab hint; a held input
cannot dismiss both. Back is also a native acknowledgement action. The cosmetic
Hangar camera continues while inventory actions remain blocked.
Main stores acknowledged roles in a content-keyed preference file, independently
of campaign saves. Unlike the source's display-time flag, native history commits
only after acknowledgement, so leaving before reading retains the hint. Returning
or starting another pilot with the same content does not replay read guidance.


`board_ui` imports MissionListWindow and MissionWindow geometry, atlas associations,
localization IDs, client layout, reward notation and description backing. MissionBoard
browses a snapshot of native contract offers and their station/visit/index references.
Info shows the supplied contract description or the original hidden-job text. Client
names, portraits, professions, difficulty and rewards all come from generated offers
using imported catalogue data. Keyboard/controller focus and touch share the same
selection; Back leaves Info before leaving the board. Portrait windows preserve the
original canvas proportions. Paid and unsupported offers cannot be accepted.

Main compares both the displayed offer and reference with the current native board
before asking Session to begin that contract. Browsing never advances or saves the
pilot. Existing Session guards own availability, encounter construction and settlement.
Native text wrapping, scrolling, focus and error notices supplement the original art;
source pixel rounding and every localized layout have not been exhaustively matched.


`station_ui.destination` imports PlanetInfoWindow's standalone box/list geometry.
DestinationMenu reuses the shared original row, preview, credit and footer artwork
with the supplied map labels. Shared station rendering exposes read-only hooks for
the selected preview and row values; station home retains its current-location data.
Unvisited destinations mask technology/trade. Flight/bribe rows use a captured native
travel quote. Current location omits Travel; unaffordable/active-job choices explain
why it is disabled. Main rejects a changed departure, visit or fare before Session
settles travel. A successful journey saves once and enters the destination dock.

Info temporarily hides map/search controls, preserving their selection and focus
on return. Its scenic background uses the selected location without changing Session.
DestinationScene uses the imported CutScene9/10 selectors, camera offsets and
projection, station depth and special station override. These previews contain no
dock traffic or generic asteroid field. A closed-form coupled relaxation and
interpolation advance the cosmetic camera independently of redraw frequency.
The hidden scene stops advancing and is retired on return. Original integer
truncation in the camera's intermediate states is not reproduced.


## Defeat and checkpoint recovery

The importer recovers `defeat_ui` text associations and backdrop geometry from
supported source consumers. `DefeatMenu` reuses the shared original ChoiceWindow.
Ship loss, objective loss and deadline failure select supplied messages. Load opens
a recovery menu shared with Pause. Autosave resumes its complete state; departure
and station snapshots roll back the whole pilot without granting rewards. Missing
checkpoints are disabled. Older saves without snapshots offer a separately confirmed
station recovery that retains current inventory/credits and repairs the ship.

`Session.load_retry` validates primary and backup files and rejects dead or failed
pilots. Both defeat retry and title Continue use this recovery path. Main's shared
save entry point preserves the last viable checkpoint after defeat, including after
leaving for the title and when closing or backgrounding the application. Survival
retains its separate run/result archive. Optional `checkpoints` metadata travels
inside the atomic pilot save and its backup; it is excluded from simulation captures
to prevent nested histories. Campaign, contract and free-flight departures capture
station and departure states. Saving at a station updates that snapshot and clears
the previous departure. Recovery validates the selected snapshot through the normal
restore path, including content identity and pilot slot. Checkpoint metadata itself
needs no schema bump; older saves remain readable through normal migrations.


Desktop presentation uses half the imported phone composition scale; mobile retains
full scale. `presentation/bitmap_font.gd` centralizes this policy and the font adapter.
Desktop menus use Godot's bundled scalable font, with imported layout height stored
separately from FontFile.fixed_size. Mobile still builds its font from the supplied
atlas. Desktop wrapped text uses its rendered font metrics; simulation radio timing
continues to use the imported text/glyph declarations. Shared dialogue and recovery
panels use one antialiased rounded fill with imported colors and corner extent,
preventing seams between translucent sprites and the panel fill. Icons and portraits
remain the original imported art.

Flight HUD creation selects the flight camera after clearing station/menu scenery.
This order prevents menu cleanup from stealing the active camera during exploration
undock, resumed flight and pause return.


Player steering reads the ship catalogue's type association and the supplied
four-entry agility table. Bounded readers also recover angular-unit conversion,
turn caps, response and release declarations, visual banking and follow-camera
blend factors, tied to the source's requested reference interval. The independent
`player_steering.gd` controller integrates angular velocity and displacement over
time, including ramp-to-limit and release boundaries. Analog input uses the
source square response; mouse displacement enters through a native rate adapter.
Yaw and pitch follow the cockpit basis; only the rendered hull receives bank.
Inversion affects mouse, controller and touch pitch; keyboard direction remains
unchanged. Native throttle, strafe, autopilot and camera framing remain extensions.

Content cache schema 78 requires reimporting older caches to recover these new
declarations. Campaign/exploration save schema 29 and survival schema 11 store
yaw/pitch angular velocity with motion state; previous saves migrate to a neutral
turn. New checkpoint snapshots use the same migration and validation paths.
Continuous-time integration avoids the original per-frame rounding and timing artifacts;
it does not claim bit-identical physical-device handling.


`original_flight_controls` defaults false, including when absent from existing
preferences. Off restores direct mouse steering, linear 1.2 rad/s keyboard/stick
response and the native steering profile. Chase presentation is shared across modes.
On selects the reconstructed source-based profile. Switching clears pending mouse
and angular state without changing heading; opening a save in default mode also
clears angular state. Inversion remains limited to mouse/controller/touch pitch.

The source clears its directional flags before the angular decay pass. The native
controller therefore applies continuous damping during input too: drive minus drag
when building speed, drag when reducing same-direction deflection, and drive plus
drag during countersteering until crossing zero. Segment integration handles this
crossing explicitly. Original integer rounding and per-frame cap/decay offsets are
not replicated. Banking gets a native 60 ms exponential presentation filter to
reduce small, intermittent mouse-packet jitter; it never changes the flight frame.
The mode's help describes the iPhone reconstruction and native mouse adaptation.


In both chase-control modes, the rendered hull takes its base orientation
from the camera, then applies the smoothed cosmetic roll/pitch. Its local basis
compensates for the physical ship's heading, so camera follow lag does not add
visible ship yaw. Camera updates refresh this basis without advancing the bank
filter again. The physical ship retains movement, aiming, collision and saved
orientation. First-person and authored external cameras retain the physical hull frame. This is a native presentation adjustment informed by
reference footage, not a new original-binary behavior claim.

Flight feedback imports the player boost envelope, perspective angles, moving-star
sprite rectangles/dimensions and the boost sound binding. The player uses the same
imported burner envelope as NPC engines, driven by its explicit boost state. A
successful activation plays the registered cue on the effects bus. Boost FOV,
particles, exhaust and sound apply to both steering modes. Native particle updates
normalize the source's frame-based movement to simulation time; pausing freezes
feedback. The imported field drifts at a fixed rate because the original hull always
cruises, so the remake's throttle scales that drift by the measured forward travel
and stops spawning while the ship is stationary; boost keeps its imported rate.
Cosmetic particle positions and trail history are recreated on load.

Fighter ribbons reuse the imported trail material, widths and history capacities.
Allegiance selects campaign colors; Survival archetypes select the imported tier
colors while retaining the ship ribbon's texture coordinates. Source ship-type
exclusions and the large ship's two attachment offsets remain data-driven. Trails
are owned by each ship visual and discarded on destruction or respawn.

Player hit presentation now passes the incoming world-space direction to the
imported flash mesh. Render completion acknowledges a flash before a subsequent
simulation step may clear it, preserving impacts across multiple fixed updates
per draw. Sound players are cached per registered cue: different variants overlap
and repeated variants restart their own voice. Source-derived shake duration and
coordinate scaling drive a temporary camera offset for surviving hits in both
control schemes, without altering physical ship motion or extending an active
shake on subsequent hits. Import schema80 carries these declarations; campaign29
and Survival11 save formats are unchanged.


### Fixed flight framing, mission departure and action freeze

Both chase-control modes retain a fixed screen anchor below the reticle while
pitch smoothing and cosmetic bank interpolation continue; yaw follows the physical
firing direction immediately. The visible hull pitches and rolls relative
to the camera; framing does not change simulated steering, inertia or position.

Import schema81 selects the friendly station-local trail branch and recovers
mission-success camera offsets, the closing transition interval, victory music
and boost/missile button opacity. On success, an invulnerable cosmetic departure
continues through closing radio and the reward receipt under a camera with a fixed
world position. Settlement still waits for dialogue and happens once. Departure
behind a settled receipt cannot mutate the save or grant additional rewards.

Action freeze is a remake feature available from Pause or P. It suspends the flight
scene and its audio, permits orbit/pan/zoom and hiding controls, and restores the
previous camera and processing state on exit. Its inspection camera does not
modify gameplay or saves. Campaign29 and Survival11 saves remain compatible.


### Flight feedback and portable saves

Import schema82 adds Radar music declarations and ObjectGun projectile meshes.
Active enemy radar contacts switch to a random choice of the two supplied battle
tracks after the source one-second delay. Peaceful flight returns after four seconds;
Survival keeps battle music between waves. Cosmetic music selection uses its own RNG.
Faction/actor gun profiles select the supplied projectile meshes while preserving
explicit special weapon profiles and independent Survival bindings.

The chase reticle still projects the simulated firing direction. Camera yaw now
keeps it aligned horizontally with the visible nose in both steering modes.
The mission-success camera begins ahead of the ship using the signed source offset,
then tracks its flyby from a fixed world position. Existing projectiles and wrecks
use detached cosmetic clocks; freighters keep their transit velocity while rewards
and simulation remain settled.

While a scripted sequence owns the scene the flight HUD is hidden entirely, matching
the supplied render pass that skips the ego bars, radar and Hud draw and ignores
touch for that time. Mission dialogue is drawn outside that pass and stays visible,
as it does for ordinary radio messages during play. Keyboard and controller pause
remain available as a remake convenience.

Touch steering belongs to the supplied stick alone. Once grabbed it follows the
finger anywhere on screen, clamped to the authored radius, as the source does;
empty space no longer starts a steering gesture.

Supplied static bodies never steer, so placed mission hulls keep the orientation
they were given: transit groups face their imported velocity and stationary hulls
hold their placement. Only scenery debris with no declared behavior still tumbles.

MotionSteering supplies optional calibrated gravity-based phone tilt with a dead
zone, smoothing, sensitivity and recentering. Native gravity/accelerometer and browser
DeviceMotion inputs are supported, both normalized to screen-space gravity pointing
down at rest, so a right-edge-down roll steers right like a stick pushed right.
Absolute tilt avoids integrated gyro drift; this is not a reconstruction of GOF2
sensor tuning. Only the horizontal direction has been corrected from device reports.

Ship catalogue information and exchange confirmation list supplied mount counts
for each weapon category, including unsupported categories with zero slots.
SaveTransfer validates all portable data before staging a sibling save directory,
preserving prior files in a timestamped backup and replacing the directory only
after all writes succeed. Transfers require identical IPA content identities and
contain only pilot/survival data. Native dialogs and browser upload/download share
this validation path. Campaign29 and Survival11 save formats are unchanged.
