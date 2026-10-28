BEEBASM?=beebasm
PYTHON?=python

# A make command with no arguments will build the SNG47 variant of the BBC
# Master port with the standard commander, and report whether the game
# binaries still match the originals (crc32)
#
# The port (docs/README.md) is built without the copy protection, whose
# encryption ranges and checksums are tied to the original's addresses (as
# with "encrypt=no" in the original's Makefile: no encryption, no checksum
# tests, and the commander file checksum set at the address that the
# assembler reports). It is the SNG47 variant only: the Master Compact
# variant has neither the sideways RAM nor the shadow RAM that the port's
# memory map uses
#
# Optional arguments for the make command are:
#
#   commander=max       Start with a maxed-out commander
#
#   match=no            Do not attempt to match the original game binaries
#                       (i.e. omit workspace noise)
#
#   verify=no           Do not compare the game binaries with the originals
#
#   moon=scenery        The moon is not solid (no MOONHIT: elite-moon.asm),
#                       for a lockstep comparison with SNG47 in a system
#                       with a moon (SNG47 has none, so flying into the moon
#                       diverges from it there)
#
#   bands=on            Banded planets: a quarter of the crater planets, by
#                       the system's seed, are drawn with latitude bands
#                       (gfx-planet7.asm's pf_bands); off by default, when no
#                       planet has bands and their code is assembled out
#
#   rings=on            Planet rings: an eighth of the systems, by the seed,
#                       have a dotted ring (gfx-planet7.asm's pf_ring,
#                       gfx-frame.asm's f_ring); off by default, when no
#                       planet has a ring and their code and variables are
#                       assembled out
#
# So, for example:
#
#   make commander=max match=no verify=no
#
# will build the port with a maxed-out commander, no workspace noise and no
# crc32 comparison
#
# The following variables are written into elite-build-options.asm depending on
# the above arguments, so they can be passed to BeebAsm:
#
# _VERSION
#   4 = BBC Master
#
# _VARIANT
#   1 = SNG47
#
# _MAX_COMMANDER
#   TRUE  = Maxed-out commander
#   FALSE = Standard commander
#
# _REMOVE_CHECKSUMS
#   TRUE  = Disable checksum routines (always, in the port)
#
# _MATCH_ORIGINAL_BINARIES
#   TRUE  = Match binaries to released version (i.e. fill workspaces with noise)
#   FALSE = Zero-fill workspaces
#
# _MOON_SOLID
#   TRUE  = Flying into the moon kills us, as the planet does (the default)
#   FALSE = The moon is scenery only (moon=scenery)
#
# _PLANET_BANDS
#   TRUE  = Banded planets (bands=on)
#   FALSE = No banded planets (the default)
#
# _PLANET_RINGS
#   TRUE  = Planet rings (rings=on)
#   FALSE = No planet rings (the default)
#
# The build (docs/memory-map.md):
#
#   * 2-build-files/dashboard.py draws the CMYK dashboard image (DIALS1.bin,
#     which elite-data.asm includes as BDATA) and writes the tables that the
#     dashboard's routines include (dashtab-*.asm), into 3-assembled-output
#
#   * 2-build-files/lightpass.py writes a copy of gfx-light.asm for each of
#     its passes (gfx-light-4.asm: L_SUN, at bank 4's end; gfx-light-6.asm:
#     L_REC, in bank 6), with the other half assembled out, into
#     3-assembled-output
#
#   * 2-build-files/streams.py emits elite-source.asm in three passes, low,
#     hot and cold (docs/memory-map.md, "The source and its passes"). First
#     ("measure") it writes the hot pass in one copy, and the hot data in
#     one, which elite-measure.asm assembles for the size of each block
#     (measure-symbols.txt). Then ("place") it flows the hot pass and the
#     hot data through their containers by those sizes (flow.txt), and
#     writes a copy of elite-source.asm for each place a pass goes (the
#     configuration, the low pass, the hot pass's three containers, the cold
#     pass) and of elite-data.asm (the hot data in HAZEL and in bank 4, the
#     cold data, the dashboard image), each with the other lines blanked,
#     into 3-assembled-output
#
#   * BeebAsm assembles the dashboard image (BDATA), then elite-layout.asm,
#     which assembles the copies in turn, each at its own address, and saves
#     the game's images: BCODE, HICODE, BANK4, HAZEL and COLD7
#
#   * 2-build-files/layout-info.py takes the addresses the loader needs from
#     the game's symbols, bankcheck.py checks the banking rules, and
#     starocc.py proves that no star can show through a fill (R_STARPLOT's
#     rule); the build fails if either fails
#
#   * then the loader, the README, the commander checksum and the disc

ifeq ($(commander), max)
  max-commander=TRUE
else
  max-commander=FALSE
endif

ifeq ($(match), no)
  match-original-binaries=FALSE
else
  match-original-binaries=TRUE
endif

ifeq ($(moon), scenery)
  moon-solid=FALSE
else
  moon-solid=TRUE
endif

ifeq ($(bands), on)
  planet-bands=TRUE
else
  planet-bands=FALSE
endif

ifeq ($(rings), on)
  planet-rings=TRUE
else
  planet-rings=FALSE
endif

.PHONY:all
all:
	echo _VERSION=4 > 1-source-files/main-sources/elite-build-options.asm
	echo _VARIANT=1 >> 1-source-files/main-sources/elite-build-options.asm
	echo _REMOVE_CHECKSUMS=TRUE >> 1-source-files/main-sources/elite-build-options.asm
	echo _MATCH_ORIGINAL_BINARIES=$(match-original-binaries) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MAX_COMMANDER=$(max-commander) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MOON_SOLID=$(moon-solid) >> 1-source-files/main-sources/elite-build-options.asm
	echo _PLANET_BANDS=$(planet-bands) >> 1-source-files/main-sources/elite-build-options.asm
	echo _PLANET_RINGS=$(planet-rings) >> 1-source-files/main-sources/elite-build-options.asm
	$(PYTHON) 2-build-files/dashboard.py 3-assembled-output
	$(PYTHON) 2-build-files/lightpass.py
	$(PYTHON) 2-build-files/streams.py measure > 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-measure.asm -d > 3-assembled-output/measure-symbols.txt
	$(PYTHON) 2-build-files/streams.py place >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 3-assembled-output/elite-data-bdata.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout.asm -d > 3-assembled-output/symbols.txt
	$(PYTHON) 2-build-files/layout-info.py
	$(PYTHON) 2-build-files/bankcheck.py
	$(PYTHON) 2-build-files/starocc.py 3-assembled-output
	$(BEEBASM) -i 1-source-files/main-sources/elite-loader.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-readme.asm -v >> 3-assembled-output/compile.txt
	$(PYTHON) 2-build-files/elite-checksum.py -u -rel1 -c 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-disc.asm -boot M128Elt -do 5-compiled-game-discs/elite-master-sng47.ssd -title "E L I T E"
	cp 5-compiled-game-discs/elite-master-sng47.ssd solid-elite-bbc-master.ssd
ifneq ($(verify), no)
	@$(PYTHON) 2-build-files/crc32.py 4-reference-binaries/sng47 3-assembled-output
endif

.PHONY:verify
verify:
	sh 6-harness/verify.sh

.PHONY:b2
b2:
	curl -G "http://localhost:48075/reset/b2"
	curl -H "Content-Type:application/binary" --upload-file "5-compiled-game-discs/elite-master-sng47.ssd" "http://localhost:48075/run/b2?name=elite-master-sng47.ssd"
