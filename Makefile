BEEBASM?=beebasm
PYTHON?=python
DISC?=oaknut-disc

# A make command with no arguments will build the SNG47 variant with the
# standard commander, and report whether the game binaries still match the
# originals (crc32)
#
# This is the BBC Master port (docs/README.md): its code moves, so it is built
# without the copy protection, whose encryption ranges and checksums are tied
# to the original's addresses (as with "encrypt=no" in the original's
# Makefile: no encryption, no checksum tests, and the commander file checksum
# set at the address that the assembler reports)
#
# Optional arguments for the make command are:
#
#   variant=<release>   Build the specified variant:
#
#                         sng47 (default)
#                         compact
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
# will build the SNG47 variant with a maxed-out commander, no workspace noise
# and no crc32 comparison
#
# The following variables are written into elite-build-options.asm depending on
# the above arguments, so they can be passed to BeebAsm:
#
# _VERSION
#   4 = BBC Master
#
# _VARIANT
#   1 = SNG47 (default)
#   2 = Master Compact
#
# _MAX_COMMANDER
#   TRUE  = Maxed-out commander
#   FALSE = Standard commander
#
# _REMOVE_CHECKSUMS
#   TRUE  = Disable checksum routines
#   FALSE = Enable checksum routines
#
# _MATCH_ORIGINAL_BINARIES
#   TRUE  = Match binaries to released version (i.e. fill workspaces with noise)
#   FALSE = Zero-fill workspaces
#
# The verify argument is passed to the crc32.py script, rather than BeebAsm

ifeq ($(commander), max)
  max-commander=TRUE
else
  max-commander=FALSE
endif

unencrypt=-u
remove-checksums=TRUE

ifeq ($(match), no)
  match-original-binaries=FALSE
else
  match-original-binaries=TRUE
endif

ifeq ($(variant), compact)
  variant-number=2
  folder=compact
  suffix=-compact
  boot=-opt 2
else
  variant-number=1
  folder=sng47
  suffix=-sng47
  boot=-boot M128Elt
endif

.PHONY:all
all:
	echo _VERSION=4 > 1-source-files/main-sources/elite-build-options.asm
	echo _VARIANT=$(variant-number) >> 1-source-files/main-sources/elite-build-options.asm
	echo _REMOVE_CHECKSUMS=$(remove-checksums) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MATCH_ORIGINAL_BINARIES=$(match-original-binaries) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MAX_COMMANDER=$(max-commander) >> 1-source-files/main-sources/elite-build-options.asm
	$(BEEBASM) -i 1-source-files/main-sources/elite-loader.asm -v > 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-source.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-source.asm -d > 3-assembled-output/symbols.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-data.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-readme.asm -v >> 3-assembled-output/compile.txt
	$(PYTHON) 2-build-files/elite-checksum.py $(unencrypt) -rel$(variant-number) -c 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-disc.asm $(boot) -do 5-compiled-game-discs/elite-master$(suffix).ssd -title "E L I T E"
ifneq ($(verify), no)
	@$(PYTHON) 2-build-files/crc32.py 4-reference-binaries/$(folder) 3-assembled-output
endif
ifeq ($(variant), compact)
	$(DISC) create 5-compiled-game-discs/elite-master$(suffix).adf --title "E L I T E" --geometry m
	$(DISC) opt 5-compiled-game-discs/elite-master$(suffix).adf RUN
	$(DISC) cp -r 5-compiled-game-discs/elite-master$(suffix).ssd:* 5-compiled-game-discs/elite-master$(suffix).adf
	$(DISC) mkdir 5-compiled-game-discs/elite-master$(suffix).adf:$$.E
endif

.PHONY:b2
b2:
	curl -G "http://localhost:48075/reset/b2"
ifeq ($(variant), compact)
	curl -H "Content-Type:application/binary" --upload-file "5-compiled-game-discs/elite-master$(suffix).adf" "http://localhost:48075/run/b2?name=elite-master$(suffix).adf"
else
	curl -H "Content-Type:application/binary" --upload-file "5-compiled-game-discs/elite-master$(suffix).ssd" "http://localhost:48075/run/b2?name=elite-master$(suffix).ssd"
endif

.PHONY:verify
verify:
	sh 6-harness/verify.sh
