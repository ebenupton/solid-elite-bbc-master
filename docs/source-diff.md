# The original's source: what the port has changed

`1-source-files/main-sources/elite-source.asm` is meant to be Mark Moxon's BBC
Master Elite source (SNG47) as released, with the port's placement done by `Area:`
tags and emission passes ([memory-map.md](memory-map.md), "The source and its
passes"), and its own code reached by hooks. This report measures how far the
file is from that, line by line, and sets out how to bring it back. The numbers are for the source after step 0
(below), which fixed the trivial comment and blank-line changes.

## How the comparison was made

The pristine source is the original's as this repository's history has it at
b892ec6, Mark Moxon's main branch (elite-source-code-bbc-master), which the port
starts from. The comparison is

    git diff --diff-algorithm=histogram -U0 b892ec6 -- 1-source-files/main-sources/elite-source.asm

which removes or changes 4,340 of the original's 48,616 lines and adds 4,883 (the
file is now 49,159 lines). Without blank lines that is 3,536 and 4,354. Before
step 0 it was 4,377 and 4,896 (3,572 and 4,362 without blank lines). Myers'
algorithm gives 4,292 and 4,835; the classification below uses histogram, which
pairs the hunks better.

`2-build-files/sourcediff.py` classifies every one of those lines. Run it from
the repository's root: `python3 2-build-files/sourcediff.py [--base REV] [--rev
REV] [--routines] [--themes] [--lines FILE]`. It defaults to b892ec6 and the
working tree of the repository it is in, and its docstring gives the rules. It
reads each -U0 hunk as a change group and takes a line's statement to be its text before any
comment (a backslash outside quotes), with the whitespace normalised. Then:

* a statement that appears on both sides of a group is kept, and only its comment
  has changed;
* a group that removes no statement and adds at most four, all calls, jumps,
  immediate loads, stores, a compare or a skip, with at least one naming port code
  or a port variable, is a hook;
* a group that swaps one JSR or JMP for another (with an optional NOP) is a
  redirected call;
* a block whose header Name: the original does not have is a port routine written
  into the file (DIALS counts as one, as it replaces DIALS parts 1 to 4);
* an added comment line in a run of comment that says "Port" is a Port: note;
* blank lines, and comment lines that are not Port: notes, belong to their group:
  they are real edits when the group changes statements, and allowed when it does
  not.

The line counts in this report are the script's. The descriptions come from reading
the hunks and the Port: notes.

**Moves.** None are left. A matching of all removed lines against all added lines
(made on the development tree's copy of the file, which differs from this one
only within a few rewritten routines) finds 46 lines in runs of three or more that reappear elsewhere: header frames, and
fragments copied into rewritten routines (ADD's tail in MAD, DVID4's loop in
STARS1). Now that the source is back in the original's order, every block is at its
original place.

**The earlier audit.** It counted about 1,600 lines changed or removed and 2,580
added. That is close to the statement counts here (1,769 and 2,699 real), and
neither count includes comments or blanks. Its figures could not be
reproduced exactly. The difference fits the commits made since then and the moves it set
aside, which have now gone.

## Summary

Lines removed or changed in the original, and lines added:

| Kind                                            | Removed/changed | Added |
|-------------------------------------------------|----------------:|------:|
| Allowed: Area: tags                              |               - |   256 |
| Allowed: Port: notes                             |               - |   620 |
| Allowed: hooks (inserted calls, minimal glue)    |               - |    34 |
| Allowed: IF/ENDIF (the solid moon)               |               - |     2 |
| Allowed: comment reworded, statement unchanged   |             533 |   228 |
| Allowed: blank lines outside edits               |               7 |    35 |
| **Allowed, total**                               |         **540** | **1,175** |
| Real: statements removed or changed / added      |           1,717 |  1,772 |
| Real: redirected calls                           |              26 |    26 |
| Real: IF/ELIF/ENDIF removed (_COMPACT branches)  |              26 |     - |
| Real: port routines written into the file        |               - | 1,423 |
| Real: comments removed with code / on new code   |           1,234 |   157 |
| Real: blank lines in edited groups               |             797 |   330 |
| **Real, total**                                  |       **3,800** | **3,708** |

(The Port: notes row counts only free-standing comment lines. Port: text that sits
on a statement line is counted with the statement.)

By statements alone, 1,769 of the original's statements are removed or changed, and
2,699 statements are added that the rules do not allow; 901 of those are in the
port routines. The allowed side has 168 statements: 132 kept with a new
comment, 34 in hooks and the 2 conditionals.

Step 0 removed 37 of the removed/changed lines and 13 of the added ones, all on
the allowed side. The real edits are unchanged by it, apart from one blank line
moved between two of them.

So only about one line in eight of the removals, and one in four of the additions,
is of an allowed kind. The real edits fall into nine groups:

| Group                                   | Removed/changed | Added |
|-----------------------------------------|----------------:|------:|
| 1 Memory map and build                  |              68 |    48 |
| 2 One screen, split timer, interrupts   |             208 |    70 |
| 3 ACCCON by TSB/TRB                     |              12 |    12 |
| 4 CMYK dashboard                        |           1,209 |   842 |
| 5 Renderer: record instead of draw      |             914 |   403 |
| 6 Speed rewrites                        |             971 | 2,140 |
| 7 Passes and banks                      |              15 |    15 |
| 8 Disc commands                         |              11 |   175 |
| 9 Unused code and tables removed        |             392 |     3 |

## The real edits by routine

Counts are removed/changed and added lines, comments and blanks of the edit
included. Routines with fewer than about 15 lines are grouped.

**1 Memory map and build** (68, 48)

* (configuration) 50, 4: CODE% &1300 to &1EE8, LOAD% = CODE%. The
  data addresses (XX21, E%, KWL%, KWH%, QQ18, SNE, ACT, TKN1, and RUPLA, RUGAL and
  RUTOK with their _COMPACT branch) are deleted, as elite-data.asm is assembled in
  the same pass; commbuf moved; HOMEBANK and COLDBANK added.
* WP 4, 36: ORG &0E41 to &0841 (below page &0D); DASHV, the dashboard's
  variables; `ORG CODE%` commented out, as elite-layout.asm places the passes;
  commbuf = LSX2; ASSERTs.
* F% 14, 0: the closing BCODE SAVE and the checksum PRINTs are removed.
* FONT%, log, K%: `ALIGN &100` and FONTPAD% before the font, ALIGN before the log
  tables (they no longer follow the font), page-&0D ASSERTs. (The INCLUDE and
  INCBIN paths are the original's: this repository has the original's layout.)

**2 One screen, split timer, interrupts** (208, 70)

* IRQ1 89, 5: rewritten. Timer 1 is tested first. There is no switch to mode 2 and
  no dashboard palette (one MODE 1 screen in a CMYK palette). The timer is not
  restarted at vsync, and `JSR H_VSYNC` replaces the palette loop.
* TVT3 86, 0 and TVT1 24, 0: the palette tables, deleted.
* T1SYNC 0, 45: a port routine that starts timer 1 free-running in step with vsync.
* VSCAN 1, 5: the line count 30 becomes 72, which centres the split in the
  horizontal blanking.
* NOISE 4, 7 and SOFLUSH 2, 4: SEI/CLI become a mask of the vsync interrupt in
  the IER, so the split's timer 1 interrupt is never held off. NOISE's unreachable
  `BVC P%+3 : ASL A` is also removed.
* DOVDU19 0, 4: VNT3 is now a two-byte variable here, as IRQ1's palette loop is
  gone.

**3 ACCCON by TSB/TRB** (12, 12)

* setzp, getzp, LOIN: each `LDA #%00001111 : STA VIA+&34` (and back) becomes TSB or
  TRB of bits 1 and 2, so that ITU and IFJ are kept. The same change also appears in
  HLOIN, PIXEL, TTX66, CLYNS and CHPR (group 5), at about 20 sites in all.
* getzp: the store of ROMSEL bank 6 is removed, as getzp is cold and NEWBRK pages
  the home bank itself.

**4 CMYK dashboard** (1,209, 842): Master's mode 2 dashboard is replaced by the demo
port's 256 x 56 MODE 1 image in shadow RAM, with the tables generated by
dashboard.py.

* SCAN 290, 150: rewritten. It draws a 3 x 2 dot and a one-pixel stick through
  ddot and generated tables, and leaves COL, X1, Y1, Y2 and the registers as
  Master's does.
* DIALS parts 1 to 4 (255, 0) are replaced by one DIALS block (0, 246).
* DILX 143, 55 (only the DIL entry is kept), DIL2 76, 50, MSBAR 73, 59, DOT 25, 43,
  SPBLB 36, 8, ECBLB 30, 6, SPBT 34, 1, ECBT 34, 1 and PZW 12, 4: rewritten for
  2 x 2 dither cells.
* CPIXK 88, 0 is deleted; ddot 0, 72 takes its place. CTWOS 35, 0 is deleted.
* DSEG 0, 89 and DILI 0, 33: port routines (a segment drawer and indicator caches).
* ADDK 76, 25: rewritten as the port's ADD/MU8 code (it runs with ACCCON X set).

**5 Renderer: record instead of draw** (914, 403): ships, dots, lines, text and the
hangar are recorded for the frame layer instead of being drawn.

* HANGER 243, 0, HAS2 56, 0, HAL3 47, 0, HAS3 42, 0 and DVID4K 38, 0: deleted, as
  G_HANGAR draws the hangar. HALL 2, 1 calls G_HANG0 and jumps to G_HANGAR; HAS1
  2, 1 jumps to G_HLL9.
* LL9 parts 9 to 12 (100, 1; 131, 0; 21, 2; 41, 2), LSPUT 68, 0 and Shpt in SHPPT
  34, 2: the original's line drawing and the ship line heap are deleted. Part 9
  records the ship (H_EE31), LSCLR returns as LSC2 did, and SHPPT records the dot
  (G_SHPPT).
* LL9 part 1 20, 1: the LSNUM/LSNUM2 set-up is deleted. Part 5 0, 1: a hook (GFAR).
* SHAND 0, 99, S_SHIP 0, 48 and SPLV 0, 39: port routines (the handedness of a
  ship, recording it, and the splinter's faces).
* LL9F 0, 16 and LL9B 0, 37: port routines (LL9 then a frame). TITLE, ESCAPE,
  BRIEF, PAUSE and PAS1 call them instead of LL9.
* PIXEL2 17, 23, PIX1 (group 6), and pxpat 0, 38 with pxpatd 0, 14: the stardust's
  record-mode test is patched into PIX1, H_STAR and H_STAROFF once per pass. FLIP,
  nWq, STARS2 and STARS6 call pxpat or pxpatd (nWq adds a NOP to keep its size).
* CHPR 9, 12, TTX66 4, 13, CLYNS 4, 6, HLOIN 6, 12 and PIXEL 6, 12: hooks (H_CHAR,
  H_DEL, G_DIRECT, H_CLYNS, H_HLOIN, H_DOT) together with the TSB/TRB edits.
  `JSR TTX66` becomes TTX66M in CHPR and cls, as TTX66 is now in bank 4.
* Small edits: DOEXP 3, 3 (PTCLS becomes H_PTCLSE, and a branch to an RTS in the
  other pass), SIGHT 3, 7 (H_SIGHT, and its own RTS in place of LO2), BOMBOFF
  (LOIN becomes H_LLINE), DEATH and the main game loop (M% becomes H_MFRAME), WARP
  (GWARP).

**6 Speed rewrites** (971, 2,140): cycle work from the grind loops and the demo port,
each with a Port: note claiming identical results.

* Multiplication by quarter squares (QSL/QSH, elite-qs.asm): MULT3 47, 126,
  MULT1 96, 27, MU11 73, 48, MLS1 52, 37, MLTU2 28, 70 and SQUA2 2, 30. MULTU, MLU1, MLU2 and MU6 are merged, and their headers deleted.
  FMLTU 3, 9 self-modifies its log operand.
* Addition and division: MAD 1, 64 and ADD 56, 15 (laid out page by page, with the
  common case first), DVID4 31, 55, DVID3B2 41, 76 with DVL9a 0, 44 (the rare paths
  moved out of line), TIS2 19, 33 (unrolled), LL5 35, 36, LL38 5, 4, TIS1 1, 0 and
  TAS3 4, 5 (calls madq).
* Stardust: STARS1 64, 345, the largest single edit. Multipliers are patched into
  inlined MLSA, MLSB and MLUQ, and DV42 and the ADDs are inlined. PIX1 1, 29
  inlines ADDK.
* Ships: LL51 54, 58 with LL51L 0, 129 (the logs patched into nine inline
  products), LL9 parts 6 to 8 (42, 33; 5, 9; 13, 3), LL62 3, 1 and LL145 1, 1.
* Orientation: MVS5 90, 229 (both ADDs inlined, rare paths after it) and MVS4 14,
  19 (skips MAD when the angle is zero).
* Main loop: MALC 0, 51 and MALW 0, 30 are port routines that copy a ship's block
  unrolled for slots 0 to 5; main flight loop parts 4, 6 and 7 jump to them and
  inline MAS4.
* Other: BLINE 55, 58, ex 15, 30 with QQ18IX 0, 38 and TT43 0, 15 (token lookup by
  a 16-entry index, kept in one page), and FILLKL 37, 74 (the keyboard is scanned
  by column on CA2, with the vsync mask).
* PLS22 81, 93, PLL4F 0, 114 and pl4pat 0, 75: planet detail. These blocks are all
  `Area: none`, so none of this code is emitted (see below).

**7 Passes and banks** (15, 15)

* JMTB 12, 12: the EQUWs of hot targets name their stubs (x4_TT27, x4_DASC and so
  on). Token 31 points at DASC, as OTHERFILEPR is removed.
* YESNO 2, 2, ANGRY 1, 1 (and DOEXP, SIGHT and SFRMIS in other groups): a branch
  to an RTS that is now in another pass becomes `BNE P%+3 : RTS`, or is retargeted.

**8 Disc commands** (11, 175)

* DOSCLI 0, 166: a port routine (with DOSNMI) that stashes HAZEL and DFS's state
  around OSCLI and restores the NMI handler. GTDIR, CATS, DELT, wfile and rfile call
  it instead of OSCLI.
* savosc and lodosc 2, 2 each: the buffer address in the command strings is
  `STR$~(commbuf)` instead of E7E.

**9 Unused code and tables removed** (392, 3): LL28's tail 45, NUMBOR 42, DEEORS 40
and DEEOR 21 (the copy protection; the port builds with _REMOVE_CHECKSUMS), wtable
37, TT214 35, SCTBX1 and SCTBX2 23 each, SWAPPZERO 17, beamcol 14, SFRMIS 14 (its
_COMPACT branch and yetanotherrts), MUT3 10, DVLOIN, OTHERFILEPR and MUT2 9 each,
NMIpissoff 8, INCYC, backtonormal, CLDELAY and yetanotherrts
5 each. Smaller ones are HLOIN22, the spare RTS in S%, the RTSs after rfile and
WARP, and hyp1's JSR TT111 (TT18 now calls hyp1, not hyp1+3). Each has a `Port:
removed` note.

## Edits in code that is not emitted

PLS22, PLL4F and pl4pat are `Area: none`, as are PL9 parts 2 and 3. streams.py
emits only their labels and an RTS. The speed work in PLS22 (81, 93), the two port routines
written into these blocks (189 added lines), and the H_MERID hook in PL9 part 2
therefore assemble nothing. PLS22 can go back to the original text now, and PLL4F and
pl4pat can come out of the file. The binary changes only by the two stub RTSs those
blocks emit.

## Step 0: trivial fixes (done)

These changes were comments and blank lines only. No statement changed, and the
statement sequence of the file was checked to be identical before and after. A
build with `make` gave every image in 3-assembled-output and the disc
byte-identical to the build before the edits, and bankcheck.py passed. The
changes:

* DETOK: the two comments wrapped mid-sentence ("Load the" / "character at
  offset Y") are joined again. (In this repository they already were.)
* The eight commented-out `\SAVE` lines (ELTA to ELTH) have the original's
  3-assembled-output paths again. (In this repository they already had them.)
* Blank lines: the extra ones before `.F%`, after HAS1, after HME2's SAVE, after
  MULT1 and after LL9 part 8's `JMP LL50` are removed, and the missing one between
  T1SYNC's RTS and DOVDU19's header is added.
* The original's wording is restored on unchanged statements, with the port's
  point kept as a `Port:` line where it matters:
  * IRQ1 (the Compact's joystick, the ADC channel, the data latch, both "the MOS
    stores the value of A" comments, "the interrupt terminates here", and DL's 30,
    with Port: lines for 72 and for the reads of T1C-L and IRA that clear the
    flags);
  * DOVDU19 (with a Port: line that VNT3+1 is only a variable now);
  * WP's Address: header (with a Port: line for &0841 to &0CA9);
  * the headers of wfile and rfile (&0E7E, with a Port: line for &087E);
  * BLINE's four comments on the &FF marker and LSP;
  * yetanotherrts' header ("the SFRMIS subroutine").

Left as they are: comment rewordings inside the rewritten routines, where the
original's words would describe code that is no longer there. These are 533
removed and 228 added lines, in SCAN, DOT, CPIXK/ddot, ECBLB2, SPBLB, SPBT, ECBT,
MSBAR, DIALS, PZW, PZW2, DILX, DIL2, ADDK, STARS1, MVS5, PLS22, MLS1, MLU2, MU11,
MULT1, ex, LL9 parts 6 and 8, FILLKL and LL145. They go when those routines are
restored (steps 1, 5 and 6). The `Port:` notes and Area: tags that step 0 left are
of an allowed kind.

## Plan for removing the real edits

**Mechanisms.** Four of these are new to streams.py; the rest of the work is
moving text.

* M1 **A port source in the passes.** Add 1-source-files/main-sources/elite-port.asm,
  read by streams.py
  like elite-source.asm. Each block has a header with `Area:` and a new field,
  `Place: after <Name>`, and is emitted in that block's pass, container and unit, in
  order. This keeps the port's own routines near the code they serve without
  writing them into the original (the reasons are branch reach, fall-through, one
  page, ACCCON X).
* M2 **`Area: omitted`.** The original's text stays and nothing is emitted. It is an
  error for emitted code to reference a label in an omitted block. Fragments inside
  live routines are excluded with IF on a build option, `_PORT_OMIT`, in the
  original's own style (`_REMOVE_CHECKSUMS`).
* M3 **`Area: replaced`.** The original block stays and is not emitted. A block in
  elite-port.asm marked `Replaces: <Name>` is emitted at its place instead.
  streams.py checks that every label of the original that is referenced is
  defined by the replacement.
* M4 **Tagged patches.** A header field `Patch: <name>` names
  1-source-files/main-sources/patches/<name>.patch: exact original lines and their replacements,
  applied to that block's emitted copy only. The build fails unless each original
  line is found exactly once. This moves the edit out of the file without hiding it:
  the header says it is there. Use it only for small, scattered edits.
* M5 **Generic transforms in streams.py**, keyed by what the passes already know:
  * a conditional branch to an RTS in another pass is emitted as the inverse
    branch over an RTS;
  * a cold EQUW of a hot label is renamed to its x4_ stub, as JSR and JMP already
    are;
  * a call from the low pass to an ACCCON X block goes through its stub (TTX66M);
  * a header field `Calls: X=Y` redirects the block's calls to X.
* M6 **Build paths.** Not needed here: this repository has the original's
  layout, so the INCLUDE and INCBIN lines are already the original's (the
  development tree, with its own layout, needs links for them).

**Order.** Each step is a run of single-purpose commits. Every commit passes
6-harness/verify.sh 10000: game state identical to SNG47 in lockstep, redock,
savetest, and save files byte-identical (msavebytes.mjs). Every commit also passes
bankcheck.py with the flow fitting (3-assembled-output/flow.txt). Steps 0 to 5 should leave the
assembled images byte-identical, or differ only by moved addresses, and can be
checked with cmp of the build outputs before and after.

0. *Trivial fixes* (done, above). Comments and blank lines only; the images are
   identical.
1. *Dead code.* Restore PLS22, and move PLL4F and pl4pat out (to elite-port.asm as
   `Area: none`, or drop them if planet detail will not return). Removes 81 and 282
   real lines. Very low risk; 2 bytes.
2. *Unused code and tables* (group 9, plus TVT1, TVT3, CTWOS, CPIXK, and the
   _COMPACT branches and data addresses in the configuration). Restore them as
   `Area: omitted`, or under `IF _PORT_OMIT` for fragments. About 650 lines back.
   Low risk: a restored label must not clash with one the port has added. No
   bytes.
3. *Port routines out* (M1). DOSCLI and DOSNMI, T1SYNC, ddot, DSEG, DILI, pxpat and
   pxpatd, LL9F, LL9B, SPLV, S_SHIP, SHAND, MALC, MALW, LL51L, DVL9a and QQ18IX go
   to elite-port.asm (or the gfx files they belong with), each placed where it is
   now. The DASHV variables, HOMEBANK and COLDBANK go to the glue's equates. This
   removes about 1,000 added lines (DIALS waits for step 6). It needs the streams.py change (about 150
   lines) and must keep each falling or branching neighbour in the same unit
   (pxpatd falls into pxpat; DOSCLI into DOSNMI). Low to medium risk; no bytes.
4. *Calls and branches* (M5). Restore the 26 redirected calls and the
   branch targets. TITLE, ESCAPE, BRIEF, PAUSE, PAS1, DEATH and the main loop take a
   `Calls:` field or a hook after the call (`JSR LL9` then `JSR` the frame).
   OSCLI's callers get a hook before and after the call. JMTB, TTX66M, YESNO,
   ANGRY, DOEXP, SIGHT and SFRMIS go to the generic transforms, and hyp1 gets its
   JSR TT111 back (3 bytes, cold). About 50 lines. Low risk.
5. *Small in-place edits* (M4, after asking for each whether the edit is still
   needed):
   * the 20 or so TSB/TRB sites, the IER masking in SOFLUSH, NOISE and FILLKL, getzp's
     ROMSEL, VSCAN's 72;
   * the configuration: CODE%, WP's ORG and commbuf, and the savosc and lodosc
     strings, where commbuf moves the command strings;
   * the ALIGNs;
   * the small speed edits in PIXEL2, PIX1, LL5, LL38, LL62, LL145, TAS3, TIS1,
     FMLTU, MVS4, LL9 parts 6 to 8 and the main loop's MAS4.

   About 400 lines out of the file, into patch files of about the same size. Low
   risk: identical images by construction.
6. *Rewritten routines* (M3). This is the large step, done one routine per commit:
   * the dashboard (group 4: SCAN, DOT, the bulbs and bars, DIALS, PZW, DILX, DIL2,
     ADDK) into a gfx-dash.asm, about 2,000 lines;
   * IRQ1 into the glue's low pass, keeping the split timing;
   * the renderer's removals: HANGER and its helpers, LL9 parts 9 to 12 and LSPUT
     become omitted or replaced. Part 1's LSNUM set-up can simply come back, as it
     only writes the original's zero page;
   * the speed rewrites with whole-routine bodies: MULT1, MU11, MLS1, MULT3, MLTU2,
     SQUA2, MAD and ADD, DVID4, DVID3B2, TIS2, LL51, STARS1, MVS5, BLINE, ex and
     FILLKL, about 3,000 lines.

   Medium risk, mostly in branch reach and page placement (ex's loop in one page,
   MAD's branches within a page): the replacement must sit at the original's place,
   which M3 gives. A replacement must not be a copy of the original's routine with
   edits. Where the rewrite is mostly the original's text (STARS1, MVS5, BLINE, LL9
   parts 6 to 8), a patch (M4) or dropping the edit is better. Decide each one by
   what its cycles are worth against its bytes and complexity (the speed-ups were
   paying about 2 cycles a flight iteration per byte at the end): an edit that
   saves few cycles per byte of complexity is reverted, not moved.
7. *Keep it so.* Run 2-build-files/sourcediff.py in the gate (or in streams.py's
   checks). Any change to elite-source.asm against b892ec6 must then be an Area:
   tag or another header field, a Port: line, a hook or an IF/ENDIF. The build
   fails otherwise.

**What each step must keep.**

* Game state identical to SNG47 in lockstep, and saves byte-identical. The
  restorations in steps 0 to 4 cannot change either. Steps 5 and 6 move edits that
  already pass, and they must pass again after the move.
* Restoring LL9 part 1's writes of LSNUM and LSNUM2, and any other original write
  that the port dropped, brings the state closer to the original's.
* Space in the banks. Steps 0 to 5 add no bytes beyond step 4's few (3 for hyp1,
  about 6 for the branch transforms). Step 6 frees bytes wherever a speed edit is
  reverted instead of moved.
* The rules in [memory-map.md](memory-map.md) and
  [master-memory.md](master-memory.md): page &0D off limits, no new shadow RAM,
  and ACCCON X code and its tables in bank 4.

elite-data.asm (the EDGE macro, QQ18's padding, the second BDATA page) has not been
audited here. The same tool (with a file option) and the same plan apply to it.
