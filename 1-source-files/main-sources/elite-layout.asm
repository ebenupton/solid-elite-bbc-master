\ ******************************************************************************
\
\ elite-layout.asm - the port's memory layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles. elite-source.asm is the original's
\ main source in the original's order, emitted in three passes, each in the
\ source's order: the low pass (blocks tagged "Area: low": Elite's code that
\ must be below &3000), the hot pass (no Area field, or "Area: hot, ACCCON X")
\ and the cold pass ("Area: cold"). 2-build-files/streams.py writes a copy of
\ elite-source.asm for each place a pass goes, with the other lines blanked
\ (3-assembled-output/elite-source-<copy>.asm; the line numbers are the source's), and
\ flows the hot pass through its containers by the sizes that
\ elite-measure.asm measured (3-assembled-output/flow.txt). This file assembles the copies
\ one after the other, each at its own address. Every label is defined once,
\ in its own copy, and every block is assembled once. A call from one side
\ (the low and hot passes) to the other (the cold pass) goes through a stub
\ of its own in the glue area (elite-stubs.asm); a fall-through across the
\ line falls into a seam, a JMP to the stub at the next routine's place:
\
\   * the configuration and the workspaces (3-assembled-output/elite-source-config.asm);
\
\   * main RAM from CODE%: the glue area (elite-glue.asm, the port's own
\     code), then the low pass, both below &3000, then the hot pass's first
\     container, to &4000 (screen buffer 0 is above; all of this is saved as
\     BCODE);
\
\   * main RAM from &7000: the quarter-square tables (elite-qs.asm,
\     &7000-&73FF), then the hot pass's second container, to &8000 (saved as
\     HICODE);
\
\   * bank 4 from &8000: the hot pass's third container (the code that runs
\     with ACCCON X set first, as it comes first in the source), then the hot
\     data that HAZEL has no room for, then the renderer's routines that run
\     in game context from G_FRAME, S_SUN and L_SUN (gfx-ssun.asm,
\     gfx-light.asm's first pass; saved as BANK4);
\
\   * the cold pass, sideways RAM bank 7: elite-source.asm's cold blocks,
\     then elite-data.asm's (3-assembled-output/elite-data-cold.asm, which
\     defines the extended tokens' macros);
\
\   * HAZEL: elite-data.asm's hot data (3-assembled-output/elite-data-hot.asm;
\     after the cold pass, as RUTOK uses the extended tokens' macros);
\
\ then the renderer (elite-gfx.asm).
\ elite-data.asm's blocks tagged BDATA, the dashboard image, are assembled on
\ their own (3-assembled-output/elite-data-bdata.asm, by the Makefile).
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-config.asm"

 ORG CODE%

 INCLUDE "1-source-files/main-sources/elite-glue.asm"           \ the port's own code: the stubs, the
                                        \ renderer's glue, the G_ stubs, the hooks
.GLUE_END%

 INCLUDE "3-assembled-output/elite-source-low.asm"   \ the low pass

.LOW_END%

 PRINT "Glue area: ", ~CODE%, "-", ~GLUE_END%-1, "; low pass: ", ~GLUE_END%, "-", ~LOW_END%-1, " (the font's alignment: ", FONTPAD%, " bytes of padding); free below &3000: ", &3000-LOW_END%
 ASSERT LOW_END% <= &3000   \ the glue area and the low pass must be below
                        \ &3000: they are used while ACCCON X = 1 (shadow RAM at
                        \ &3000-&7FFF), from interrupts or from MOS vectors with
                        \ any ROM paged: the stubs, the renderer's glue and
                        \ hooks, NEWBRK, the IRQ and sound code, CHPR and its
                        \ font and UP (CATF, FLH, COMC)

 INCLUDE "3-assembled-output/elite-source-hot1.asm"  \ the hot pass: main RAM, to &4000

.HOT1_END%

 PRINT "Hot pass: main RAM ", ~LOW_END%, "-", ~HOT1_END%-1, " free ", &4000 - HOT1_END%
 ASSERT HOT1_END% <= &4000  \ (main RAM &4000-&6FFF is screen buffer 0)
 ASSERT NA2% < HOT1_END%    \ (elite-checksum.py sets the commander's checksum in BCODE)
 PRINT "S.BCODE ", ~CODE%, " ", ~P%, " ", ~LOAD%, " ", ~LOAD%
 SAVE "3-assembled-output/BCODE.unprot.bin", CODE%, P%, LOAD%

 CLEAR &7000, &C000
 ORG &7000

 INCLUDE "1-source-files/main-sources/elite-qs.asm"             \ the quarter-square tables

.QS_RUN%

 INCLUDE "3-assembled-output/elite-source-hot2.asm"  \ the hot pass: main RAM from &7400

.HOT2_END%

 PRINT "Quarter-square tables: &7000-", ~QS_RUN%-1, ", then the hot pass ", ~QS_RUN%, "-", ~HOT2_END%-1, " free ", &8000 - HOT2_END%
 ASSERT HOT2_END% <= &8000
 SAVE "3-assembled-output/HICODE.bin", &7000, &8000, &7000

 ORG &8000

 INCLUDE "3-assembled-output/elite-source-hot3.asm"  \ the hot pass: bank 4

.HOT3_END%

 INCLUDE "3-assembled-output/elite-data-hot4.asm"    \ the hot data that HAZEL has no room for

.R4_START%                              \ the renderer's code that runs in game
 INCLUDE "1-source-files/main-sources/gfx-ssun.asm"             \ context, at bank 4's end (streams.py
 INCLUDE "3-assembled-output/gfx-light-4.asm"        \ keeps its room), from G_FRAME: S_SUN,
                                        \ the sun near the planet, and L_SUN
                                        \ (gfx-light.asm's first pass), the
                                        \ light for the next iteration's ships;
 INCLUDE "1-source-files/main-sources/elite-moon.asm"           \ and from MA22, MOONHIT: the moon is
                                        \ solid (moon=on; else nothing)
.R4_END%
.BANK4_END%

 PRINT "Bank 4: hot pass &8000-", ~HOT3_END%-1, ", hot data ", ~HOT3_END%, "-", ~R4_START%-1, ", S_SUN, L_SUN (and MOONHIT) ", ~R4_START%, "-", ~R4_END%-1, " free ", &C000-BANK4_END%
 ASSERT BANK4_END% <= &C000
 SAVE "3-assembled-output/BANK4.bin", &8000, &C000, &8000

\ ******************************************************************************
\
\ Port: the cold pass (docs/memory-map.md), paged in as ROMSEL = COLDBANK
\ (7): sideways RAM bank 7 from &8000, the original's cold code and data in
\ the original's order: the blocks of elite-source.asm tagged cold (with a
\ seam, a JMP to a hot routine's stub, where a cold routine falls into a hot
\ one), then those of elite-data.asm (the extended tokens TKN1 and their
\ macros: RUPLA, RUGAL and RUTOK are hot data, in HAZEL). Saved as COLD7.
\
\ ******************************************************************************

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-source-cold.asm"

 INCLUDE "3-assembled-output/elite-data-cold.asm"    \ the extended tokens, TKN1

.COLD_END%

 PRINT "Bank 7 cold: &8000-", ~COLD_END%-1, " (the meridian window follows: elite-gfx.asm)"
 ASSERT COLD_END% <= &C000
 SAVE "3-assembled-output/COLD7.bin", &8000, COLD_END%, &8000

\ ******************************************************************************
\
\ Port: HAZEL (&C000-&DFFF), visible whatever bank is paged: the hot data,
\ elite-data.asm's blocks that are not tagged (3-assembled-output/elite-data-hot.asm,
\ which 2-build-files/streams.py writes) in the original's order from &C000: XX21,
\ E%, KWL%, KWH%, the blueprints from the missile's to the Dodo's, QQ18, SNE,
\ ACT, then RUPLA, RUGAL and RUTOK (the extended descriptions' overrides,
\ which the cold pass reads). DOSCLI stashes all of HAZEL in screen buffer 0
\ around each disc command, so the data may sit anywhere in it; nothing the IRQ handler or
\ CHPR uses during a command is here. Saved as HAZEL (it ends below &DF00: the MOS's own
\ bytes from &DF00 on are left as the loader's disc accesses left them, and
\ are not for the game's data), which the loader copies into place after its last disc
\ access (and the data as HZDATA, for the tools).
\
\ ******************************************************************************

 CLEAR &C000, &E000
 ORG &C000

.HZ_START

 INCLUDE "3-assembled-output/elite-data-hot.asm"

.HZDATA_END%

.HZ_END                 \ (HAZEL holds the game data only: the renderer
                        \ keeps nothing here, docs/memory-map.md rule 5)

 PRINT "HAZEL: game data &C000-", ~HZDATA_END%-1, ", free ", &DF00-HZ_END, " (+ 256 at &DF00, the MOS's)"
 ASSERT HZ_END <= &DF00  \ (&DF00-&DFFF is the MOS's: its FS numbers and
                        \ filing-system names, its lasting state)
 SAVE "3-assembled-output/HZDATA.bin", &C000, HZDATA_END%, &C000
 SAVE "3-assembled-output/HAZEL.bin", HZ_START, HZ_END, HZ_START

 PRINT "Addresses for the scramble routines in elite-checksum.py"
 PRINT "F% = ", ~F%
 PRINT "G% = ", ~G%
 PRINT "NA2% = ", ~NA2%

 INCLUDE "1-source-files/main-sources/elite-gfx.asm"      \ Port: the filled renderer (main RAM, banks 5 and 6,
                                  \ ANDY, and its meridian window in bank 7)
