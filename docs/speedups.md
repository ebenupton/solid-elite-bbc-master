# The speed-ups

The port's second part makes the game logic faster, one idea per commit,
without changing what it computes. Each commit keeps the game state byte
for byte the original's at every one of the gate's 10,000 iterations. The
original's wireframe drawing is still in place, and the screen is checked
too: it is the original's at every iteration. Most of the ideas come from
the port's development tree, where a long series of small, measured
speed-ups (the "grind") was made against the filled renderer. Some came from
the Demonstration Disc port. Here they are grouped by routine and idea, in
their final form, and measured afresh on this series.

## How a speed-up is measured

The gate's run is deterministic. The same build gives the same cycles to
the cycle, and the emulated Master runs at 2 MHz. So the cycles per flight
iteration that the gate prints (2,000,000 divided by the flight iterations
per emulated second) are an exact measure. Because the game state is
identical, both builds run the same flight iterations. Each figure below is
the cycles per flight iteration after the commit, and the saving against
the commit before it.

Page crossings move with the code. A commit that moves later code changes
which branches and indexed reads cross a page, by a few cycles either way,
and that is included in its figure. `6-harness/profile.mjs --pagex` counts
the crossing cycles apart. Alignment is left for a final pass, so none of
these commits pads code to keep it in place.

## What the gate checks in this part

The first four commits pass the strict comparison: every recorded byte,
the drawing temporaries included, with the screen. From ADD's MU8 on, the
port's arithmetic leaves some of the temporaries that the drawing code
shares with it (`U`, for example) differently. Nothing reads them before
writing them again. So the gate compares the game state without the drawing
temporaries and line heaps (loose mode), and with the screen: the
wireframe drawn is still the original's, pixel for pixel, at every
iteration.

## The commits

| Commit | Cycles per flight iteration | Saved | Flight it/s |
|---|---:|---:|---:|
| (the end of part 1) | 143,347 | | 13.95 |
| Multiply in MU11 by quarter squares | 141,231 | 2117 | 14.16 |
| Multiply in MULT1 by quarter squares | 140,410 | 821 | 14.24 |
| Multiply in MULTS by quarter squares | 138,286 | 2124 | 14.46 |
| Multiply in MLTU2 and MULT3 by quarter squares | 135,916 | 2370 | 14.71 |
| Subtract the common way round in ADD's MU8, and skip MULT1 for Q = 0 | 133,704 | 2212 | 14.96 |
| Take DVID4's common quotient of 0 without dividing | 131,444 | 2260 | 15.22 |
| Shorten DVID3B2's normalisation | 129,620 | 1824 | 15.43 |
| Take LL5's square root in four-step halves | 129,373 | 247 | 15.46 |
| Negate LL38's underflowed sum without the stack | 129,356 | 17 | 15.46 |
| Patch the coordinates' logs into LL51's dot products | 128,271 | 1085 | 15.59 |
| Unroll TIS2's division | 127,927 | 344 | 15.63 |
| Project only the visible vertices' coordinates in LL9 | 127,717 | 210 | 15.66 |
| Keep XX13 in X in LL145 | 127,692 | 25 | 15.66 |
| Skip MVS4's multiply when the roll or pitch is zero | 127,083 | 610 | 15.74 |
| Scan only the keyboard columns that have a key pressed in FILLKL | 124,134 | 2948 | 16.11 |
| Inline both of MVS5's ADDs | 123,478 | 656 | 16.20 |
| Specialise the stardust loop's arithmetic | 117,558 | 5919 | 17.01 |
| Unroll the main loop's copies of the ship data blocks | 116,186 | 1372 | 17.21 |
| Inline MAS4 in the main flight loop | 116,159 | 27 | 17.22 |
| Copy BLINE's points once | 115,240 | 919 | 17.36 |
| Patch the curve's multipliers into the planet's PLL4 | 113,131 | 2109 | 17.68 |
| Keep FMLTU's argument in an operand | 113,005 | 126 | 17.70 |
| Start ex's token search at the nearest sixteenth token | 112,248 | 758 | 17.82 |
| Inline ADDK in PIX1, and tighten PIXEL2 | 111,970 | 277 | 17.86 |

In all, the speed-ups save 31,377 cycles per flight iteration, 22% of the
game's time in flight: 17.86 flight iterations per emulated second, against
SNG47's 13.97 (1.278 times), with the original's wireframe drawn pixel for
pixel. Each commit's message explains its idea, and the source carries
"Port:" comments at each change.

## Where the cycles went

The biggest wins are the multiplications. A quarter-square table (2K, at
main `&7000`) replaces the shift-and-add loops of MU11, MULT1, MULTS,
MLTU2 and MULT3, which every rotation, projection and stardust step uses.
After them come the stardust loop (STL1), where the multipliers are fixed
for a whole pass or particle and are patched into the code, and LL51's dot
products and the planet's curves, where the logs of fixed arguments are
patched in once. Then come divisions that take their common case first
(DVID4, DVID3B2), the unrolled copies of the ship blocks, and the keyboard
scan, which tests 13 columns instead of 112 keys.
