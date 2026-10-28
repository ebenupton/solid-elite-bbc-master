# The BBC Master's spare memory, and what the MOS and DFS keep there

These findings come from experiments in jsbeeb's emulated Master 128, with
MOS 3.20 and the 1770 DFS 2.24. Every read and write was traced to the code
that made it, and the disc image itself was checked after each test. The
DFS code paths quoted come from the ROM images. [memory-map.md](memory-map.md)
describes how the port lays itself out in this memory.

| Region | Usable by the game? | Bytes |
|---|---|---:|
| ANDY `&8000-&8FFF` (ROMSEL bit 7) | Yes, all of it, if the MOS's VDU drivers are never used (Elite prints through its own WRCHV) and soft keys are never expanded (Master Elite sets `*FX 225,128`). Disc access does not touch it. The port's rasteriser uses it as its polygon window; the save test checks it around every disc command. | 4096 |
| HAZEL `&C000-&DFFF` (ACCCON Y) | Yes, all of it in flight. Around a disc command, keep 128 bytes, poke 6 and restore what DFS and the MOS overwrite (see below). | 8192 |
| Shadow `&3000-&3FFF` (ACCCON X) | Yes. Master Elite saves the top of zero page at `&3090-&30FF` during disc access. | 4096 |
| Shadow `&7E00-&7FFF` | Yes. It is not displayed (CRTC R6 = 31). | 512 |
| Main `&0840-&0CFF` | Yes, if the MOS's SOUND, ENVELOPE, printer, RS423, cassette and speech are unused (`&0B00-&0CFF` is unused anyway). | 1216 |
| Main `&0D00-&0DFF` | **Never** (see below). | 0 |

## Page &0D is off limits

Never write main RAM `&0D00-&0DFF` while the game is loaded. `&0D00` holds
the 1770 DFS's NMI routine, and an NMI cannot be masked: a Gotek or a late
INTRQ can deliver one at any time. `&0D9F-&0DEF` holds the extended vectors,
which ROMs on a real machine hook, so any OS call may jump into the page.
`&0DF0-&0DFF` is the ROM workspace table. A clean emulated Master has none
of those hooks, so the emulator does not show the failure, but an earlier
port that built tables in page `&0D` hung on a real Master 128.

The build asserts that nothing is assembled there. Once the game has
started, the harness fails any write to the page by code in RAM. The one
exception is `DOSNMI`, which puts back a six-byte minimal NMI handler at
`&0D00-&0D05` after each disc command (see below).

## HAZEL and the filing system

DFS 2.24 and the MOS keep this in HAZEL:

| Range | Owner | Contents |
|---|---|---|
| `&C000-&C1FF` | DFS | the catalogue cache (sectors 0 and 1 of the current drive) |
| `&C200-&C27F` | DFS | transient name buffers |
| `&C280-&C2BF` | DFS | drive state: `&C282` is the drive whose catalogue is cached, `&C287` the restore flags, `&C28B-&C28E` the track cache |
| `&C2C0-&C2FF` | DFS, **lasting** | the current drive, directory and library, the drive settings, the NMI claim count |
| `&C300-&C3BF` | DFS | the open-file table (the game opens no files) |
| `&D900-&DAFF` | ADFS's and DFS's private pages | their saved state |
| `&DC00-` | MOS | OSCLI copies the command line here |
| `&DD00-&DEFF` | none | untouched by every test |
| `&DF00-&DF47` | MOS | the filing system numbers and the filing-system name table |
| `&DFC0-&DFFF` | MOS, **lasting** | `&DFDA-&DFDB` is the current filing system's FSCV. On an error during a command, the MOS writes `&DFDC` to ACCCON if `&DFDD` is non-zero |

The MOS never touches HAZEL in flight. A disc command (SAVE, LOAD, CAT,
DELETE, DIR, DRIVE) writes `&C000-&C29E`, `&C2C0-&C2DC`, `&DC00` up to the
end of the command, `&DF00-&DF05` and `&DFC6`.

Clobber experiments found what must survive between commands. Disc access
works with all of HAZEL filled with random bytes, zeros or `&FF` between
every command, provided three things hold. First, `&C2C0-&C2FF` and
`&DFC0-&DFFF` must hold what DFS and the MOS last left there. Second,
`&C282`, `&C287` and `&C28B-&C28E` must be set to `&FF`. That makes DFS
re-read the catalogue and restore the head. Third, the command must be in
memory that the MOS can read.

The second point matters. DFS skips re-reading the catalogue while the drive
motor is still on (for about two seconds after a command) if `&C282` names
the drive. If the cache has been overwritten by then, DFS writes a catalogue
built from the overwritten cache: files are lost and the disc title is
erased.

The port keeps its game data in HAZEL, so it does this around every disc
command (`DOSCLI`):

* Copy all 8K of HAZEL to main RAM `&4000-&5FFF`, screen buffer 0, which
  is not on show while docked. The next entry to space mode starts the
  buffer afresh (`GSTASH`).
* Put DFS's and the MOS's 128 lasting bytes back from `DFSST`. The loader
  takes them after its last disc access.
* Write `&FF` to the six drive-state bytes.
* Copy the command to `&6000`. The command strings are in the cold pass,
  which is not paged in while the MOS and DFS run the command.
* Run the command.
* Stash the lasting bytes again, as `*DIR` and `*DRIVE` change them.
* Copy HAZEL back.

The error path does the same through `BRKV` (`NEWBRK` calls `DOSNMI`).
Nothing that runs during a command (the interrupt handler, the printing of a
catalogue through `CHPR`) reads HAZEL, and any write the game makes to HAZEL
goes out and comes back with the copy. So the data may sit anywhere in HAZEL
below `&DF00`. `&DF00-&DFFF` is the MOS's: game data loaded there would
overwrite its filing system table.

After each command, DFS's NMI routine is replaced by a minimal handler:
`PHA : LDA &FE28 : PLA : RTI` at `&0D00`, written with the RTI first so that
the page holds a complete handler at every step. DFS's handler uses
`&A0-&A7`, which are the game's zero page in flight. A stray NMI after
loading (seen on a real Master) would corrupt them, and could start a 1770
command. The loader installs the minimal handler too, after quietening the
1770 with a Force Interrupt.

A third-party ROM that hooks BYTEV or WORDV and writes its private page in
HAZEL on every call would corrupt the game data. The loader resets the
non-filing-system vectors to the MOS's defaults for this reason. No ROM in
the standard Master set gives itself a page other than DFS's (`&DA`) and
ADFS's (`&D9`).

## Main RAM below &0E00

| Range | Use | Spare? |
|---|---|---|
| `&0400-&07FF` | language workspace | Master Elite's `K%` and the ship line heap |
| `&0800-&083F` | MOS sound workspace | only if the MOS's IRQ code never runs (Elite's IRQ1V never passes interrupts on) |
| `&0840-&08FF` | sound channel buffers, printer buffer, envelopes | yes, if unused |
| `&0900-&0AFF` | RS423, cassette and speech buffers | yes, if unused |
| `&0B00-&0CFF` | unused on the Master | yes |
| `&0D00-&0DFF` | DFS's NMI routine, extended vectors, ROM workspace table | **never** |

The port puts Elite's workspace `WP` at `&0841-&0CA9`, the original's
`&0E41-&12A9` moved down by `&600` so that each byte keeps its place in its
page. The CMYK dashboard's variables follow it to `&0CCE`, then `VEC`, the
original IRQ1 vector, at `&0CCF`. From `&0E00` (OSHWM) up to the main code
(`&1E01`) is the renderer's shared workspace; the loader runs there first,
and its last part from `&0400`. The commander file buffer (`commbuf`, which shares its place with
`LSX2`) is at `&087E`. `*SAVE` gives commander files load and execution
addresses of 0, so their catalogue entries do not depend on the buffer. A
commander saved by the original and one saved by the port at the same state
are identical, entry and contents, and each loads in the other.

## Shadow RAM

The MOS writes shadow RAM only when its own VDU drivers drive a shadow mode,
which Elite never uses. While ACCCON X is set, all of main RAM `&3000-&7FFF`
is hidden, so code that runs with X set (Master Elite's drawing, `CHPR`) and
the data it reads must be below `&3000` or in a sideways bank.
