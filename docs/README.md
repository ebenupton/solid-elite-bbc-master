# BBC Master Elite: the port

This branch is a series of changes to Mark Moxon's annotated source for BBC
Master Elite (the Acornsoft SNG47 release), in six parts:

1. **The memory map.** The game is laid out over main RAM, sideways RAM
   banks 4 and 7, and HAZEL. This leaves main RAM `&4000-&6FFF` and banks 5
   and 6 and ANDY free for a filled renderer. The source stays in the
   original's order, with each routine's header naming the area it lives in
   ([memory-map.md](memory-map.md)).
2. **The speed-ups** of the game logic, one idea per commit
   ([speedups.md](speedups.md)). At the end of this part the game still
   draws the original's wireframe, pixel for pixel, at 17.86 flight
   iterations per emulated second against SNG47's 13.97 (1.278 times).
3. **The filled renderer** ([renderer.md](renderer.md)). Ships are filled
   and lit by the sun, the planet and the sun are discs, the screen is double
   buffered in one CMYK palette, and there are a lens flare, a filled hangar
   and the briefing's ship. This runs at 17.24 flight iterations per emulated
   second (1.234 times SNG47).
4. **Beach balls, kept rows and the layout's last changes**
   ([renderer.md](renderer.md), [memory-map.md](memory-map.md)). Meridian
   planets are beach balls again, drawn by a meridian window in bank 7, and
   close-up docking keeps the rows that the station fills. The shared
   workspace shrinks by two pages and takes the kept rows' `KF`, the port's
   own code below `&3000` becomes one area, the hangar's tables move to
   bank 6, and HAZEL holds only the game's data. This runs at 11.98 flight iterations
   per emulated second (0.857 times SNG47): a big spinning beach ball costs
   more than the original's half ellipses, and the gate's pilot starts at
   Lave, whose planet is one.
5. **Three passes** ([memory-map.md](memory-map.md)). The build emits the
   source in three passes: low (only what must be below `&3000`, after the
   port's glue area), hot (flowed by measured sizes through main RAM and
   then bank 4, the code that runs with shadow RAM paged included, with no
   separate bank 4 copy) and cold (bank 7). Each routine called between the
   hot and cold passes has a direct stub of its own, at 85 cycles a call
   against the far calls' 171, and the text printers and the routines that
   crossed most are hot. The docked screens take 4.8% fewer busy cycles
   (5,152,363 against 5,411,007, `6-harness/mdocktime.mjs`), and flight
   runs at 11.99 iterations per emulated second (0.858 times SNG47).
   Since then the frame rate is capped at 25 frames a second
   ([renderer.md](renderer.md)): no frame is on show for a single field, and
   flight runs at 11.73 (0.840 times SNG47), as the frames that were quicker
   than two fields now wait at their flip. Lessons from the port to the
   Tube then took some of that back: the beach ball's disc rows keep two
   colour boundaries a row instead of four, one-colour and emptied rows take
   the short paths, and the polygon fill has no empty-run test, for 11.82
   (0.846 times SNG47). The ships' edge lists, which nothing reads, are no
   longer assembled; with the two boundaries this freed 3.6K (HAZEL 1,919
   bytes free, bank 4 1,850, bank 5 808 more). ACCCON's top bits are left
   as the MOS set them, and BREAK now clears memory, so SHIFT-BREAK boots
   the game again.
6. **Planets** ([renderer.md](renderer.md)). One circle engine draws every
   planet's surface: the beach ball, true spherical craters, and banded
   planets and rings behind the `bands=on` and `rings=on` build options. A
   quarter of the systems have a moon, fixed in space and solid; the sun is
   drawn near the planet while the station has its slot; every disc is
   drawn incrementally; and stars go only into wholly black screen bytes.
   Flight runs at 10.29 iterations per emulated second (0.736 times SNG47),
   most of the cost in the crater system, whose two true craters cost more
   than the original's polygon crater.

Each commit builds, and each passes the gate in [6-harness](../6-harness).
The gate flies the released game and the new build side by side with a
deterministic pilot, and requires the game state to be byte for byte the
original's at every one of 10,000 main-loop iterations. While the port
still draws as the original does, it also requires the screen to match at
every iteration. The memory map's hardware findings are in
[master-memory.md](master-memory.md). [source-diff.md](source-diff.md)
measures how far `elite-source.asm` is from the original's source, line by
line, and sets out a plan to bring it back.

## Building

    make                        (BeebAsm 1.11 and Python 3, as upstream)
    make verify                 (the gate: Node.js, jsbeeb and py65, see 6-harness)
    make bands=on               (banded planets, an option: renderer.md)
    make rings=on               (planet rings, an option: renderer.md)
    make moon=scenery           (the moon not solid, for a lockstep comparison
                                 with SNG47 in a moon system: renderer.md)

`make` writes the disc to `5-compiled-game-discs/elite-master-sng47.ssd`,
copies it to `solid-elite-bbc-master.ssd` in the repository's root (the
disc to download), and writes the binaries to `3-assembled-output`. If
`python` or `beebasm` is not on the path, pass `PYTHON=` and `BEEBASM=`.
The pre-commit hook in `2-build-files/hooks` (`git config core.hooksPath
2-build-files/hooks`) refuses a commit whose root disc is not the build's. It also reports whether each game
binary still matches the original's. The disc needs a BBC Master 128 with
sideways RAM in banks 4 to 7 (links LK18 and LK19 set to RAM), and boots
with SHIFT-BREAK. The tracked outputs in `3-assembled-output` and
`5-compiled-game-discs` are refreshed at the end of each of the first three
parts, and with every commit of the fourth and fifth. The Master
Compact files there are the original's, as the port is the SNG47 variant
only.

## The copy protection

The port is built without the copy protection. The original encrypts the
main code and the data, and checks a checksum of the commander file. Both
are tied to the original's addresses, which the port changes. So the source
is assembled with `_REMOVE_CHECKSUMS` (no decryption at start-up, no
checksum test on loading a commander), and `elite-checksum.py` only sets the
commander file's checksum. It takes the addresses it needs (`F%`, `G%`,
`NA2%` and the address that BCODE loads at) from the assembler's output
(`-c 3-assembled-output/compile.txt`). This matches the original's `make
encrypt=no`.

## The results

| | Flight it/s | Against SNG47 | Cycles per flight iteration |
|---|---:|---:|---:|
| SNG47 | 13.97 | 1.000 | 143,137 |
| End of part 1: the memory map | 13.95 | 0.999 | 143,347 |
| End of part 2: the speed-ups (the original's wireframe) | 17.86 | 1.278 | 111,970 |
| End of part 3: the filled renderer | 17.24 | 1.234 | 115,992 |
| End of part 4: beach balls and kept rows | 11.98 | 0.857 | 166,950 |
| End of part 5: three passes | 11.99 | 0.858 | 166,791 |
| The 25 fps cap | 11.73 | 0.840 | 170,501 |
| The planet's z in the depth test | 11.73 | 0.839 | 170,540 |
| Lessons from the Tube | 11.82 | 0.846 | 169,148 |
| Part 6: planets | 10.29 | 0.736 | 194,288 |
| The text map's footprint, the countdown | 10.30 | 0.737 | 194,178 |
| The disc layer's rows: count and colour in one byte | 10.38 | 0.743 | 192,731 |
| Explosion clouds drawn from the ship line heap | 10.39 | 0.744 | 192,407 |

These are the gate's run: the pilot's mix of launches, fights, approaches to
the station and hyperspace jumps, over 10,000 iterations. Page `&0D` is never
written, and saved commander files are byte for byte the original's.
