# BBC Master Elite: the port

This branch is a series of changes to Mark Moxon's annotated source for BBC
Master Elite (the Acornsoft SNG47 release), in three parts:

1. **The memory map.** The game is laid out over main RAM, sideways RAM
   banks 4 and 7, and HAZEL. This leaves main RAM `&4000-&6FFF` and banks 5
   and 6 and ANDY free for a filled renderer. The source stays in the
   original's order, with each routine's header naming the area it lives in
   ([memory-map.md](memory-map.md)).
2. **The speed-ups** of the game logic, one idea per commit.
3. **The filled renderer.**

Each commit builds, and each passes the gate in [6-harness](../6-harness).
The gate flies the released game and the new build side by side with a
deterministic pilot, and requires the game state to be byte for byte the
original's at every one of 10,000 main-loop iterations. While the port
still draws as the original does, it also requires the screen to match at
every iteration.

## Building

    make                        (BeebAsm 1.11 and Python 3, as upstream)
    make verify                 (the gate: Node.js and jsbeeb, see 6-harness)

`make` writes the disc to `5-compiled-game-discs/elite-master-sng47.ssd`
and the binaries to `3-assembled-output`. It also reports whether each game
binary still matches the original's. The disc needs a BBC Master 128 with
sideways RAM in banks 4 to 7 (links LK18 and LK19 set to RAM), and boots
with SHIFT-BREAK. The tracked outputs in `3-assembled-output` and
`5-compiled-game-discs` are refreshed at the end of each part.

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

## Part 1: the memory map

| Commit | Gate |
|---|---|
| The determinism harness and the gate | passes on the unmodified source: the game state and the screen identical at all 10,000 iterations |
| The port without the copy protection | identical (strict, with the screen) |
| WP and the commander buffer below page `&0D`, and the hangar's heap | identical (strict, with the screen) |
| The layout over main RAM, banks 4 and 7, and HAZEL | identical (strict, with the screen), and the disc menu's save, load, failed load and catalogue check passes |
| The original's unreachable code and unused tables removed | identical (strict, with the screen) |

At the end of part 1 the game runs at 13.95 flight iterations per emulated
second in the gate's run, against SNG47's 13.97. Code that moved now
straddles page boundaries in new places, which costs about 200 cycles a
flight iteration (143,347 against the original's 143,137). Page &0D is
never written, and saved commander files are byte for byte the original's.
