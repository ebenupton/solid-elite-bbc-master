# The determinism harness and the gate

This folder holds the tools that check a change to BBC Master Elite against
the released game. They run the original SNG47 disc and the new build side by
side on an emulated BBC Master, fly both with the same deterministic pilot,
and compare the game state at every iteration of the main loop.

Every commit of the port passes the gate, `6-harness/verify.sh`.

## Requirements

* Node.js 20 or later.
* jsbeeb 1.6.0, the emulator, which the harness runs headless (it never
  opens a window). Run `npm install` in this folder, or point `JSBEEB` at a
  jsbeeb checkout or package directory.
* Python 3 and BeebAsm 1.11 for the build, as for the rest of the
  repository, and py65 (`pip install py65`) for the rasteriser's test.

## The gate

    make verify                 (or: sh 6-harness/verify.sh [iterations])

The gate builds the game with `make`. It then compares the released disc
(`4-reference-binaries/sng47/elite-master-sng47.ssd`, with the symbols of
the original source's build) against the new disc
(`5-compiled-game-discs/elite-master-sng47.ssd`, with its own symbols) for
10,000 main-loop iterations. Then it runs the regression checks: dock,
launch and dock again; save, load, fail to load and catalogue through the
game's disc menu; change view in flight; and pose the ships the ship audit
flagged in flight (`mshippose.mjs`). It prints `VERIFY PASS` with
the speed of both builds in flight-loop iterations per emulated second,
their ratio, and the new build's cycles per flight iteration. A run takes
about 10 minutes, or 5 once the reference run is cached in `work/`.

`MODE` sets how much the comparison covers:

* `strict` compares every byte of the recorded game state, the drawing
  temporaries and line heaps included.
* `loose` leaves out the drawing temporaries and the line heaps. This is
  for a build whose drawing code differs from the original's.
* `screen` also compares the screen (shadow RAM `&4000-&7DFF`) at every
  iteration. This is for a build that draws exactly as the original does.

`verify.sh` sets the mode the port's current state must meet.

## How the comparison works

* **Input injection** (`mlib.mjs`). The keyboard is never pressed. At
  `RDKEY+5`, just after the game scans the keyboard, the harness writes
  the key logger exactly as `FILLKL` would have for the pilot's keys, and
  `DKS5`'s single-key tests are answered the same way. Both builds see the
  same keys at the same main-loop iteration, or at the same poll of a key
  wait, however fast they run.
* **The pilot** (`mpilot.mjs`). The pilot's keys are a function of the game
  state at the start of the iteration only, so equal states give equal
  keys. It launches, fights, docks with the docking computer, trades and
  equips, and makes hyperspace and galactic jumps. It also patches the
  commander identically at `BAY` in both runs.
* **The state** (`mlib.mjs`, `regionsFor`). This is zero page, the ship
  slots `K%` and the ship line heap, the workspace `WP`, the configuration
  `UP`, the saved commander `NA%` and the sound buffers. Each region is found
  by symbol, wherever a build puts it. The state is recorded at every
  `MLOOP`.
* **What is left out.** The bytes that the interrupt handler writes in real
  time (`DL`, `JOPOS`, the sound buffers) are left out. So are the
  temporaries that hold the addresses of code or data that the port moves
  (`P`, `V`). The station's line heap pointer `LSO` is compared as the
  original's.
* **Sound.** `NOISE` would let real time leak into the game state, through
  its choice of sound channel and the carry it returns into `DORND`. So
  `SOPR` is cleared at every `NOISE` entry in both runs.
* **Boot leftovers.** At `TT170`, any byte of the compared state that the
  new build has not yet written is seeded from the reference (`--seed
  boot`). Such a byte was left by the loader, not by the game.
* **Page `&0D`.** Once the game has started, a write to page `&0D` by any
  code in RAM fails the run. The one exception is `DOSNMI`'s minimal NMI
  handler at `&0D00-&0D05` (see `docs/master-memory.md`).

## The tools

| File | What it does |
|---|---|
| `mlib.mjs` | Boots a disc on the emulated Master and runs the game under the pilot. Handles input injection, state snapshots and the screen hash, and sees through the stubs between the passes to the code that called them. |
| `mpilot.mjs` | The deterministic pilot and its commander patch. |
| `mcompare.mjs` | Compares the reference against a candidate and reports the first divergence, the speed per window and by pilot phase, and the cycles per flight iteration. |
| `mredock.mjs` | The regression check for docking, launching and docking again, with real key presses. |
| `msavetest.mjs` | Exercises the disc menu: save, load, a failed load, a catalogue and a launch. It junks the parts of HAZEL that DFS and the MOS may write at each disc command, then checks that the game data and the NMI handler survive. |
| `mstation.mjs` | The regression check for the depth test: puts a docking scene (the planet at z = &10636, just over 65536, the station dead ahead in front of it) into a freshly launched game and checks that every frame recording the station draws it. F_PLANET once kept 16 bits of the planet's z, so the station was hidden behind the planet. |
| `mshippose.mjs` | The regression check for the ships the ship audit flagged: poses the Missile and the Splinter in a flight slot at the audit's orientations, in both of the game's handednesses (as `ZINF` spawns a ship and as `TIDY` leaves it), with `LL9`'s `XX3` poisoned, and checks each screen: nothing lit outside the ship's projected hull, its body covered, and exactly its front faces filled. |
| `mboot.mjs` | Boots a build to the title screen and checks every image that the loader installs. |
| `mtrace.mjs` | Traces chosen routines and variables over chosen iterations (`mcompare.mjs --trace`). |
| `profile.mjs` | Profiles cycles by PC over exactly the gate's run, with `--pagex` for page-crossing cycles. |
| `test_raster.py`, `raster_model.py` | The filled renderer's rasteriser (banks 5 and ANDY) and the meridian window (bank 7) on py65, against a pixel-exact model of every primitive: polygons, lines, discs, stars, the dirty-row repair, the beach ball's rows (`merid`, `beachball`), the kept solid rows (`kept`). It also checks that nothing outside the screen, the rasteriser's own memory and its zero page is written. `--quick` runs in the gate; the full run takes longer. |
| `planet_analytic.py` | The reference model of the beach ball's boundaries, from the Demonstration Disc port: per row, where each great circle's projected ellipse crosses it, in floating point or exactly as the 6502 code's integer arithmetic. `test_raster.py` checks the meridian window against it. |
| `mlight.mjs` | Records what the lighting (`L_REC`) was given and wrote for every ship drawn, for `2-build-files/lightcheck.py` to check against the model. |
| `mhangar.mjs` | Screenshots of the hangar in chosen configurations, for `2-build-files/hangarinks.py`. |
| `mdocktime.mjs` | The docked screens' drawing times: boots the build as the gate does and, from the Status screen, presses each docked-screen key in turn (f8, f1 ... f7, f9), giving each screen's cycles from the key's scan to the next, and its busy cycles (less the wait for the vertical sync). The emulation is deterministic, so a build gives the same figures every run. |
| `mflarevis.mjs` | The lens flare's occlusion probes: flies the gate's pilot to an iteration, then puts the sun (and optionally a ship in front of it) on a path, and dumps each frame's back buffer with the probes in sight and their cycles, for `2-build-files/flarevis.py` to render. |
| `mflips.mjs` | The flip-interval distribution: how many fields each frame of the space view is shown for, over the gate's run (or the title screen, `--title SECS`), per pilot phase. With the 25 fps cap the shortest is 2. |
| `verify.sh` | The gate. |

### Replay tools

The tools in `beachball/` and `solidspan/` replay a session that
[elite-agent](https://github.com/8bitkick/elite-agent) played, read for
read, on a build, headless. They import the development tree's agentplay
library (`agentplay/lib.mjs`, `session.mjs` and `styles.mjs`, which drive
elite-agent's sessions), which is not part of this repository: copy it
into `6-harness/agentplay` to run them.

| File | What it does |
|---|---|
| `beachball/beachshot.mjs` | Finds the frames that draw a beach ball planet in a replayed session, records the meridian window's inputs, and screenshots chosen frames (`--dump` writes each frame's inputs and the disc layer's rows, to check against `planet_analytic.py`). |
| `solidspan/common.mjs` | Replays a session on a build (it needs `banks.txt` beside the symbols, or the banked hooks are dropped and the game never starts); the other `solidspan` tools use it. |
| `solidspan/mspeed.mjs`, `solidspan/itcyc.mjs` | The speed over windows of iterations, and the cycles of every iteration with whether it ran in K mode (the kept solid rows). |
| `solidspan/fbhash.mjs`, `solidspan/fbcmp.mjs` | Hashes of both screen buffers after every frame, and their comparison between two builds: the pixel check of the kept solid rows. |
| `solidspan/srec.mjs`, `solidspan/sdump.mjs`, `solidspan/sbound.py`, `solidspan/ssim.py` | Records the spans and buffers of each frame, bounds what keeping uniform spans could save, and replays the records through the kept rows' rules. |
| `solidspan/kprof.mjs`, `solidspan/kpc.mjs`, `solidspan/szprobe.mjs` | Cycles by label between exact iteration boundaries, cycles by PC in a range, and the recorded ships' z. |
