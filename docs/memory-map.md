# The memory map

This is where the port puts each part of BBC Master Elite (SNG47), why it
goes there, and how code in one region reaches another.
[master-memory.md](master-memory.md) covers the hardware: what the MOS and
DFS use, and which spare RAM the game may take.

The original runs from main RAM `&1300-&7F48`, which includes the half of
main RAM that the shadow screen hides. It keeps its data (the ship
blueprints, the text tokens, the sine and arctan tables) in sideways RAM
bank 6. The port moves the code out of main RAM `&3000-&7FFF` (apart from
`&7000-&7FFF`), so that the filled renderer can use main `&4000-&6FFF` as a
second screen buffer. It spreads the code over main RAM, sideways RAM banks
4 and 7, and HAZEL. Every routine stays at its place in the original's
source.

## The rules the layout follows

1. **ACCCON X.** With X = 1, shadow RAM appears at `&3000-&7FFF` and main
   RAM there is hidden. Code that runs with X = 1, and the data it reads,
   must not be in main `&3000-&7FFF`. That covers Master's drawing (lines,
   pixels, text, the dashboard) and `CHPR`. The original's order puts
   what this code reaches in main RAM (`ADDK`, the font, the log tables,
   `UP`) in the main code's head, below `&3000`. The build asserts that the
   head ends below `&3000`.
2. **Interrupts and MOS vectors.** The IRQ arrives with any bank paged and
   with X either way. WRCHV (`CHPR`) and BRKV (`NEWBRK`) are entered with
   any ROM paged. Their handlers, and everything they touch, are in main RAM
   below `&3000`. They reach banked code only through far calls, which page
   the bank in and then page the caller's bank back. `NEWBRK` pages bank 4
   itself first.
3. **One sideways bank at a time.** Elite's home bank, bank 4, is paged
   whenever game code runs. So main RAM, HAZEL and bank 4 call each other
   and read each other's data directly. The main code itself runs on from
   main RAM into bank 4. The cold area, bank 7, is reached only through
   far-call stubs.
4. **The game data is in HAZEL.** HAZEL is visible whatever bank is paged.
   The data sits in the original's order from `XX21` at `&C000`. `NWSHP`
   reads past `E%`, to `E%-1,Y`, for the planet and the sun, into the
   missile's blueprint, as in the original, so the order matters.
5. **HAZEL and disc access.** DFS and the MOS overwrite parts of HAZEL
   during a disc command and keep lasting state there. `DOSCLI`, through
   which every OSCLI goes, stashes all of HAZEL in main `&4000-&5FFF`. It
   puts the filing system's lasting bytes back, invalidates DFS's catalogue
   cache and copies the command to `&6000`. Then it makes the command and
   copies everything back ([master-memory.md](master-memory.md)).
   `&DF00-&DFFF` is the MOS's and holds no game data.
6. **Page `&0D`** is never written, except by `DOSNMI`'s minimal NMI handler
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
  and the dashboard. These go into bank 4, after the run.
* **`Area: cold`** is the cold area, sideways RAM bank 7. This is code that
  runs on docked screens or a few times a flight: the docked screens, text
  and tokens, charts, the market, equipment, the title and start-up, save
  and load, launch, docking and hyperspace, the missions.

In `elite-data.asm`, untagged blocks are the hot data (HAZEL), `Area: cold`
is the token tables (bank 7, after the cold code), and `Area: BDATA` is the
dashboard image.

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

## The map

| Region | Addresses | What |
|---|---|---|
| Zero page, stack, `K%` | `&0000-&00E3`, `&0100-&01FF`, `&0400-&07FF` | as in the original |
| `WP` | main `&0841-&0CA9` | Elite's workspace, the original's `&0E41-&12A9` moved down by `&600` (each byte keeps its place in its page), with the commander file buffer `commbuf` (`LSX2`) at `&087E` |
| The main code's head | main from `CODE%` (`&1300`) to `HEAD_END%`, below `&3000` | the original's head, `TVT3` to `UP`, in its order: the palettes, the IRQ handler and the sound, `CHPR`, `ADDK`, the font and the log tables (page aligned), `UP`. Then the **low area** (`elite-low.asm`): the blocks tagged low (`stackpt`, `NEWBRK`), the far calls (`elite-far.asm`) and `DOSCLI`'s stash of the filing system's lasting bytes (`DFSST`) |
| The run, in main RAM | from `HEAD_END%` | the rest of the main code in its order, with the stubs of the cold routines whose places are in it, to a marker before `TACTICS`, below `&4000` |
| Main `&4000-&6FFF` | | not used by the game. `DOSCLI` borrows `&4000-&6000` during a disc command (HAZEL's stash and the command) |
| The run, continued | main `&7000-&7FFF`, then bank 4 from `&8000` | from `TACTICS` on to `F%`, through `&8000` into bank 4. Main `&7000-&7FFF` is never on show (the dashboard is in shadow RAM), and the code there never runs with ACCCON X set |
| Bank 4, tagged blocks | after `F%` | Master's drawing (`ylookup`, `SCAN`, `LOIN`, `HLOIN`, `PIX1`, `PIXEL`, `TTX66`, `CLYNS`, the tables `TWOS` and the rest) and the dashboard (`DIALS` and its helpers, the bulbs, `MSBAR`) |
| HAZEL | `&C000-` | the hot data in the original's order: `XX21`, `E%`, `KWL%`, `KWH%`, the blueprints, `SNE`, `ACT`. `HANGHEAP` (`&DE00`) is the hangar's ship line heap (see `HAS1`). `&DF00-&DFFF` is the MOS's |
| Bank 7, the cold area | `&8000-` | the cold blocks of `elite-source.asm` in its order, with the stubs out of the cold area at their routines' places, then the cold data: `QQ18` and the extended tokens `TKN1`, `RUPLA`, `RUGAL` and `RUTOK` |
| Shadow `&3000-&3FFF` | `&3090-&30FF` | the zero-page save (`setzp`, `getzp`), as in the original |
| Shadow `&4000-&7DFF` | | the screen, as in the original |

Banks 5 and 6 and ANDY are not used yet. They are reserved for the filled
renderer.

Where main RAM below `&4000` ends is a marker at a routine boundary that
nothing falls into or branches across. A banner before `TACTICS` saves BCODE
and sets `ORG &7000`. `TACTICS`'s seven parts branch into one another, so it
moves as a whole. `TACTICS` is the latest place at which the port's final
layout still fits below `&4000`. `elite-layout.asm` saves main
`&7000-&7FFF` as HICODE and bank 4 as BANK4.

## The loader

The loader (`M128Elt`, at `&0E00`, as in the original) first checks that
sideways banks 4 to 7 are RAM. It sets up the screen as the original does.
Then it loads each file to `&1300` and copies it into place, using its table
`FTAB`:

* BDATA, the dashboard image, goes to shadow `&7000-&7DFF`.
* BANK4 goes to bank 4.
* COLD7 goes to bank 7.
* HAZEL is staged at main `&4000`.
* HICODE goes to main `&7000-&7FFF`.

Then it loads BCODE to its address and changes directory to E. Its last
part runs from `K%` (`&0400`). It takes DFS's and the MOS's lasting bytes
into `DFSST`, copies HAZEL into place, quietens the 1770 and installs the
minimal NMI handler, resets the non-filing-system vectors to the MOS's
defaults, and starts the game at `S%`. `S%` is in the cold area, and the
loader takes its address and bank from the game's symbols
(`3-assembled-output/game-addresses.asm`, from `layout-info.py`).

## What is not in the original's order

* **Stubs.** Each emission holds a far-call stub at the place of each
  routine that lives on the other side. `streams.py` generates them; they
  are not in the source.
* **The low area.** `stackpt` and `NEWBRK` are at their original place in
  the source but are emitted at the end of the head. `NEWBRK` is the
  original with three lines that page bank 4 in, and a call of `DOSNMI`.
* **Port routines next to the routine they serve.** `DOSCLI` and `DOSNMI`
  are at the end of the cold code.
* **Changed for the layout.** A few short branches into a routine that is
  now in another area return through their own `RTS` instead (`DOEXP`,
  `YESNO`, `ANGRY`, `SIGHT`). `getzp` no longer pages bank 6 in. `CHPR`
  reaches `TTX66` in bank 4 through a far call (`TTX66M`), as it runs as
  WRCHV with any ROM paged. `HANGER`, in the cold area, computes the screen
  row's page instead of reading `ylookup` in bank 4.
* **Placement by the build.** `CODE%` is `&1300`. The font and the log
  tables must start a page (`FONT%` is a page number, and `FMLTU` and
  `LL28` index `log` by the argument), so an ALIGN before the font pads the
  head (the build prints the padding, `FONTPAD%`). `TVT3` must also start a
  page, and it is the first table at `CODE%`.
