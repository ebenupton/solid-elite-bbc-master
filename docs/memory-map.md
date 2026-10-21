# The memory map

This is where the port puts each part of BBC Master Elite (SNG47) and of the
filled renderer, why it goes there, and how code in one region reaches
another. [master-memory.md](master-memory.md) covers the hardware: what the
MOS and DFS use, and which spare RAM the game may take.
[renderer.md](renderer.md) describes the renderer itself.

The original runs from main RAM `&1300-&7F48`, which includes the half of
main RAM that the shadow screen hides. It keeps its data (the ship
blueprints, the text tokens, the sine and arctan tables) in sideways RAM
bank 6. The port moves the code out of main RAM `&3000-&7FFF`, apart from
`&7000-&7FFF`, so that main `&4000-&6FFF` can be the second screen buffer.
It spreads the game over main RAM, sideways RAM banks 4 and 7, and HAZEL.
The renderer goes in banks 5 and 6 and ANDY, with its shared state and glue
in main RAM below `&3000`. Every routine of the game stays at its place in
the original's source.

## The rules the layout follows

1. **ACCCON X.** With X = 1, shadow RAM appears at `&3000-&7FFF` and main
   RAM there is hidden. Code that runs with X = 1, and the data it reads,
   must not be in main `&3000-&7FFF`. That covers Master's drawing (the
   docked screens' text and lines, the dashboard), `CHPR` and the frame
   layer. The original's order puts what this code reaches in main RAM
   (`ADDK`, the font, the log tables, `UP`) in the main code's head, below
   `&3000`. The renderer's shared workspace and its glue are below `&3000`
   too. The build asserts that the head and the low area end below
   `&3000`.
2. **Interrupts and MOS vectors.** The IRQ arrives with any bank paged and
   with X either way. WRCHV (`CHPR`) and BRKV (`NEWBRK`) are entered with
   any ROM paged. Their handlers, and everything they touch, are in main RAM
   below `&3000`. They reach banked code only through far calls, which page
   the bank in and then page the caller's bank back. `NEWBRK` pages bank 4
   itself first.
3. **One sideways bank at a time.** Elite's home bank, bank 4, is paged
   whenever game code runs. So main RAM, HAZEL and bank 4 call each other
   and read each other's data directly, and the main code runs on from main
   RAM into bank 4. Every other bank is reached through a stub that pages it
   in and pages the caller's bank back. `&F4` always matches ROMSEL.
4. **The renderer is in banks 5 and 6 and ANDY only.** ANDY (ROMSEL bit 7)
   overlays `&8000-&8FFF` of the paged bank:
   * ROMSEL `&85` is the rasteriser's polygon window: ANDY over bank 5,
     whose `&9000-&BFFF` is the rasteriser's shared region.
   * ROMSEL 5 is its disc window.
   * The frame layer is bank 6.
   Nothing calls between the two windows, and the shared region refers to
   neither. Each bank keeps its private tables. The state that more than one
   bank reads, or that the IRQ handler or code running with ACCCON X set
   reads, is the renderer's shared workspace, in main RAM below the main
   code.
5. **The game data is in HAZEL.** HAZEL is visible whatever bank is paged.
   The data sits in the original's order from `XX21` at `&C000`. `NWSHP`
   reads past `E%`, to `E%-1,Y`, for the planet and the sun, into the
   missile's blueprint, as in the original, so the order matters. The
   hangar's tables follow the data.
6. **HAZEL and disc access.** DFS and the MOS overwrite parts of HAZEL
   during a disc command and keep lasting state there. `DOSCLI`, through
   which every OSCLI goes, stashes all of HAZEL in screen buffer 0 (main
   `&4000-&5FFF`). It puts the filing system's lasting bytes back,
   invalidates DFS's catalogue cache and copies the command to `&6000`. Then
   it makes the command and copies everything back
   ([master-memory.md](master-memory.md)). The next entry to space mode
   starts buffer 0 afresh. `&DF00-&DFFF` is the MOS's and holds no game
   data.
7. **The screen and the split.** Main `&4000-&6FFF` is screen buffer 0 and
   shadow `&4000-&6FFF` buffer 1. Shadow `&7000-&7DFF` is the dashboard.
   Main RAM under the dashboard (`&7000-&7FFF`) is never on show, as the
   split is never late ([renderer.md](renderer.md), "Dashboard split
   timing"). So it holds the high code and the main code's run. Code that
   must not be interrupted by the vsync handler masks only CA1 in the System
   VIA's IER. It never uses SEI, which would hold the split off.
8. **Page `&0D`** is never written, except by `DOSNMI`'s minimal NMI handler
   at `&0D00-&0D05`. The build asserts that nothing is assembled there.

## The source and its emissions

`elite-source.asm` is Mark Moxon's main source in the original's order, and
`elite-data.asm` is his data source. Each routine or table's header names
the area it lives in:

    \       Name: TT219
    \       Type: Subroutine
    \   Category: Market
    \    Summary: Show the Buy Cargo screen (red key f1)
    \       Area: cold

* **No Area field** means the main code's **run**. This starts in main RAM
  at `CODE%`, moves to `&7000` at a marker (see below) and continues through
  `&8000` into bank 4.
* **`Area: low`** is for routines that must be in main RAM below `&3000`
  but whose original place is later in the run (`stackpt`, and `NEWBRK`,
  which BRKV enters with any ROM paged). They are assembled at the end of
  the run's head.
* **`Area: bank 4`** is for code that runs with ACCCON X set and does not
  fit below `&3000`, and for the tables it reads: Master's drawing routines
  for the docked screens' text and lines, and the CMYK dashboard. These go
  into bank 4, after the run.
* **`Area: cold`** is the cold area, sideways RAM bank 7. This is code that
  runs on docked screens or a few times a flight: the docked screens, text
  and tokens, charts, the market, equipment, the title and start-up, save
  and load, launch, docking and hyperspace, the missions.

In `elite-data.asm`, untagged blocks are the hot data (HAZEL), `Area: cold`
is the token tables (bank 7, after the cold code), and `Area: BDATA` is the
dashboard image (`2-build-files/dashboard.py` draws it).

BeebAsm assembles with one location counter, and banks 4 and 7 share the
addresses `&8000-&BFFF`. So `2-build-files/streams.py` writes one copy of
each source per area into `3-assembled-output`, with the other areas' lines
blanked, so that line numbers stay the source's. `elite-layout.asm`, the
file that the Makefile assembles, INCLUDEs the copies in turn, each at its
own address. Each label is defined once and each block is assembled once.

**Stubs at their routines' places.** Each emission is the original in its
order, with a far-call stub wherever a routine lives on the other side. The
hot side is the run, the low area and bank 4. The cold side is the cold
area. The source calls everything by the original's names. In the cold copy
`streams.py` renames each cold label `X` to `X_C`, and turns each call from
cold code to hot code `H` into a call of `x4_H`. It then writes the stubs
into the copies, on the line that defines each routine:

    .TT22    JSR far7 : EQUW TT22_C     (hot copy: the cold routine's place)
    .x4_TT26 JSR far4 : EQUW TT26       (cold copy: the hot routine's place)

A routine that never returns (`BAY`, `DEATH2`, `TT170`; `BEGIN`, `GOIN`,
`FRCE`) gets a jump stub (`far7j`, `far4j`). Four of the original's
fall-throughs cross the hot/cold line: `RES2` into `ZINF`, `Ze` into
`DORND2`, `SOLAR` into `NWSTARS` and `BEGIN` into `TT170`. Each falls into
the stub at the next routine's place. The stub calls the routine, which
returns to the falling routine's caller with the caller's bank back, just
as the fall-through did.

`elite-far.asm` holds the far-call helpers, in the low area. A far call
reads the stub's address while the caller's bank is still paged, keeps the
caller's ROMSEL on the stack, pages the target in, calls it and pages the
caller's bank back. A, X, Y and the flags pass both ways. A far call costs
about 100 cycles and adds three bytes to the stack. `&F4` always matches
ROMSEL.

**Checks at every build.** `streams.py` checks four things. Each block's
IF ... ENDIF nesting is balanced. A block that can fall through its end is
followed by a block of its own area, or by a block of the other side whose
first statement is its entry label. No other fall-through crosses areas.
Every stub has its own line. Then `2-build-files/bankcheck.py` checks every
reference in the per-area copies. Branches never cross areas. Cold code
reaches hot code only through stubs, and hot code reaches cold code only
through stubs. A reference to the other side's data is only ever an address
(`#LO`/`#HI`).

## Calls between regions

Main RAM, HAZEL and bank 4 call each other directly. Everything else goes
through a stub:

| Kind | Where | Pages |
|---|---|---|
| far7 and far7j stubs (`.TT22 JSR far7 : EQUW TT22_C`), generated into the hot copies | the run, each at its cold routine's place | the cold area in, then the caller's bank back |
| far4 and far4j stubs (`.x4_TT26 JSR far4 : EQUW TT26`), generated into the cold copy | the cold area, each at its hot routine's place | bank 4 in, then the cold area back |
| `G_` stubs | the low area (`gfx-gstubs.asm`; `G_CHAR`, `G_DELCHAR` and `G_CLRTEXT` in `gfx-lowhooks.asm`) | bank 6 in, then bank 4 back (or the caller's bank, for the text stubs) |
| `T_` trampolines | the low area (`gfx-tramp.asm`) | the rasteriser in (ROMSEL `&85` for `T_POLY` and `T_LINE`, bank 5 for the rest), then bank 6 back |

In the gate's run the flight iterations make about 0.5 far calls each,
nearly all of them `x4_TT26` from the cold area's token printing. The `G_`
and `T_` stubs are the renderer's hot path by design. `bankcheck.py` checks
the rules for every reference: branches never cross areas; each side
reaches the other only through stubs; the renderer's banks are entered only
through their stubs or by address, call nothing in another bank, and read
main RAM only below `&3000`. A deliberate exception is marked `bankcheck:
ok` on its line.

## The map

| Region | Addresses | What |
|---|---|---|
| Zero page, stack, `K%` | `&0000-&00E3`, `&0100-&01FF`, `&0400-&07FF` | as in the original |
| `WP` | main `&0841-&0CCE` | Elite's workspace, the original's `&0E41-&12A9` moved down by `&600` (each byte keeps its place in its page), with the commander file buffer `commbuf` (`LSX2`) at `&087E`; then the CMYK dashboard's variables (`DASHV`), as the dashboard runs with ACCCON X set |
| The shared workspace | main `&0E40-&1EDB` | the renderer's shared state, one block that ends where the main code starts: the rasteriser's per-call scratch, `DFSST` (`DOSCLI`'s stash), the dirty extents, the disc rows' boundaries, the stars (`elite-gfx.asm`) |
| The main code's head | main from `CODE%` (`&1EDC`) to `HEAD_END%` (`&2DD1`), below `&3000` | the original's head, `VEC` to `UP`, in its order: the IRQ handler and the sound, `CHPR`, `ADDK`, the font and the log tables (page aligned: `CODE%` is chosen so that this pads nothing), `UP`. Then the **low area** (`elite-low.asm`): the blocks tagged low (`stackpt`, `NEWBRK`), the far calls (`elite-far.asm`) and the renderer's glue (`gfx-gvars.asm`, `gfx-tramp.asm`, `gfx-lowhooks.asm`, `gfx-gstubs.asm`, `gfx-hooks.asm`) |
| The run, in main RAM | from `HEAD_END%` to below `&4000` | the rest of the main code in its order, with the stubs of the cold routines whose places are in it, to a marker before `TACTICS` |
| Buffer 0 | main `&4000-&6FFF` | the screen; during a disc command, HAZEL's stash and the command |
| The high code, then the run | main `&7000-&7FFF` | the quarter squares `QSL` and `QSH` (`elite-hi.asm`, page aligned at `&7000`), then the run from `TACTICS` on, through `&8000` into bank 4 |
| Bank 4 | `&8000-&B0EF` | the run's continuation, to `F%`; then the blocks tagged bank 4: Master's drawing for the docked screens (`ylookup`, `LOIN`, `HLOIN`, `PIX1`, `PIXEL`, `TTX66`, `CLYNS` and their tables) and the CMYK dashboard (`SCAN`, `DOT`, `ddot`, the bulbs, `MSBAR`, `DIALS` and its helpers, with the tables `dashboard.py` writes) |
| Bank 7, the cold area | `&8000-&B08F` | the cold blocks of `elite-source.asm` in its order, with the stubs out of the cold area at their routines' places, then `QQ18` and the extended tokens |
| ANDY, the rasteriser's polygon window | `&8000-&8FD9` (ROMSEL `&85`) | `R_POLY` and `R_LINE` (`gfx-raster_poly.asm`, `gfx-raster_line.asm`) |
| Bank 5, the rasteriser | `&8000-&8F76` (ROMSEL 5), `&9000-&BF7C` | the disc window (`gfx-raster_disc.asm`); the shared region (`gfx-raster.asm`: the boundary arrays, `R_SETBUF`, the per-x tables, the 24 row-run pages at `&A000`, the stars; `gfx-flare.asm`; `gfx-raster_lcold.asm`) |
| Bank 6, the frame layer | `&8000-&BFB8` | `gfx-frame.asm`, `gfx-faces.asm`, `gfx-light6.asm`, `gfx-light.asm`, `gfx-frame_cold.asm`, `gfx-flare6.asm`, `gfx-hangar.asm`; then its state: the half-widths, the display list (with `F_INIT`, `gfx-finit.asm`), the text map and the cells' shown states |
| HAZEL | `&C000-&DDF3` | the hot data in the original's order: `XX21`, `E%`, `KWL%`, `KWH%`, the blueprints, `SNE`, `ACT`; then the hangar's tables (`gfx-hangar-hz.asm`). `&DF00-&DFFF` is the MOS's |
| Shadow `&3000-&3FFF` | `&3090-&30FF` | the zero-page save (`setzp`, `getzp`), as in the original; nothing else |
| Buffer 1, the dashboard | shadow `&4000-&7DFF` | the screen |

Where main RAM below `&4000` ends is a marker at a routine boundary that
nothing falls into or branches across. A banner before `TACTICS` saves BCODE,
sets `ORG &7000` and INCLUDEs the high code. `TACTICS`'s seven parts branch
into one another, so it moves as a whole; with it below `&4000`, the next
boundary, `DOCKIT`, would overflow.

Free space: 653 bytes below `&4000` (559 of them below `&3000`), 3,856 at
the end of bank 4, 3,952 in bank 7, 268 in HAZEL, 137 and 131 (and 252 in
the row runs' tails) in bank 5, 38 in ANDY, 71 in bank 6, and 50 and 143 in
`WP`'s pages and the shared workspace.

## The loader

The loader (`M128Elt`, at `&0E00`, as in the original) first checks that
sideways banks 4 to 7 are RAM. It sets up the screen as the original does,
with the CMYK palette. Then it loads each file to `&1300` and copies it into
place, using its table `FTAB`:

* BDATA, the dashboard image, goes to shadow `&7000-&7DFF`.
* BANK4 goes to bank 4 and COLD7 to bank 7.
* RASTA goes to ANDY (ROMSEL `&85`).
* BANK5 goes to bank 5 and BANK6 to bank 6.
* HAZEL is staged at main `&4000`.
* HICODE goes to main `&7000-&7FFF`.

Then it loads BCODE to its address (`&1EDC`) and changes directory to E. The
loader is in the shared workspace's place, so its last part runs from `K%`
(`&0400`), where it is copied first. That part takes DFS's and the MOS's
lasting bytes into `DFSST`, copies HAZEL into place, quietens the 1770 and
installs the minimal NMI handler, and resets the non-filing-system vectors
to the MOS's defaults. Then it calls `G_INIT`, which sets up the renderer's
state, and starts the game at `S%`. `S%` is in the cold area, and the loader
takes its address and bank from the game's symbols
(`3-assembled-output/game-addresses.asm`, from `layout-info.py`).

## What is not in the original's order

* **Stubs.** Each emission holds a far-call stub at the place of each
  routine that lives on the other side. `streams.py` generates them; they
  are not in the source.
* **The low area.** `stackpt` and `NEWBRK` are at their original place in
  the source but are emitted at the end of the head. `NEWBRK` is the
  original with three lines that page bank 4 in, and a call of `DOSNMI`.
* **Port routines next to the routine they serve.** These are `ddot` (at
  `CPIXK`'s place), `DILI` and `DSEG` (after `DIL2`), `pxpatd` and `pxpat`
  (before `PIX1`), `MALW` and `MALC` (after part 6 of the main flight
  loop), `DVL9a` (after `DVID4`), `PLL4F` and `pl4pat` (after `PLS22`),
  `LL9F`, `LL9B` and `LL51L` (after `LL51`), `QQ18IX` (after `ex`) and
  `T1SYNC` (after `VSCAN`). `DOSCLI` and `DOSNMI` are at the end of the cold code.
* **Changed for the layout.** A few short branches into a routine that is
  now in another area return through their own `RTS` instead (`DOEXP`,
  `YESNO`, `ANGRY`, `SIGHT`). `getzp` no longer pages bank 6 in. `CHPR`
  reaches `TTX66` in bank 4 through a far call (`TTX66M`), as it runs as
  WRCHV with any ROM paged.
* **Removed.** The original's unreachable code and unused tables, and
  Master's direct drawing of ships, which nothing uses any more. Each
  original routine keeps its header with a "Port: removed" note.
* **Port additions outside the source**, each in its own file with a header
  saying why: the low area (`elite-low.asm`), the far calls
  (`elite-far.asm`), the high code (`elite-hi.asm`), the layout
  (`elite-layout.asm`) and the renderer (`elite-gfx.asm` and the `gfx-*.asm`
  files).
