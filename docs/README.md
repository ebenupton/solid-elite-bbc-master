# BBC Master Elite: the port

This branch is a series of changes to Mark Moxon's annotated source for BBC
Master Elite (the Acornsoft SNG47 release). Each commit builds, and each
passes the gate in [6-harness](../6-harness): the game state must be byte for
byte the released game's at every one of 10,000 main-loop iterations flown by
a deterministic pilot.

## Building

    make                        (BeebAsm 1.11 and Python 3, as upstream)
    make verify                 (the gate: Node.js and jsbeeb, see 6-harness)

`make` writes the disc to `5-compiled-game-discs/elite-master-sng47.ssd`. It
also reports whether each game binary still matches the original's.

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
