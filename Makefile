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
# The build (docs/memory-map.md):
#
#   * 2-build-files/dashboard.py draws the CMYK dashboard image (DIALS1.bin,
#     which elite-data.asm includes as BDATA) and writes the tables that the
#     dashboard's routines include (dashtab-*.asm), into 3-assembled-output
#
#   * 2-build-files/streams.py writes a copy of elite-source.asm for each of
#     the port's areas (the run, the low area, bank 4, the cold area) and of
#     elite-data.asm (the hot data, the cold data, the dashboard image), each
#     with the other areas' lines blanked, into 3-assembled-output
#
#   * BeebAsm assembles the dashboard image (BDATA), then elite-layout.asm,
#     which assembles the copies in turn, each at its own address, and saves
#     the game's images: BCODE, HICODE, BANK4, HAZEL and COLD7
#
#   * 2-build-files/layout-info.py takes the addresses the loader needs from
#     the game's symbols, and bankcheck.py checks the banking rules
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

.PHONY:all
all:
	echo _VERSION=4 > 1-source-files/main-sources/elite-build-options.asm
	echo _VARIANT=1 >> 1-source-files/main-sources/elite-build-options.asm
	echo _REMOVE_CHECKSUMS=TRUE >> 1-source-files/main-sources/elite-build-options.asm
	echo _MATCH_ORIGINAL_BINARIES=$(match-original-binaries) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MAX_COMMANDER=$(max-commander) >> 1-source-files/main-sources/elite-build-options.asm
	$(PYTHON) 2-build-files/dashboard.py 3-assembled-output
	$(PYTHON) 2-build-files/streams.py > 3-assembled-output/compile.txt
	$(BEEBASM) -i 3-assembled-output/elite-data-bdata.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout.asm -d > 3-assembled-output/symbols.txt
	$(PYTHON) 2-build-files/layout-info.py
	$(PYTHON) 2-build-files/bankcheck.py
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
