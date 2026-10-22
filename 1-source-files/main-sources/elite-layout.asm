\ ******************************************************************************
\
\ elite-layout.asm - the port's memory layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles. elite-source.asm is the original's
\ main source in the original's order, and the header of each routine or
\ table names the area it lives in (no Area field: the main code's run;
\ "Area: bank 4"; "Area: cold"). Banks 4 and 7 share the addresses
\ &8000-&BFFF and BeebAsm assembles a file with one location counter, so
\ 2-build-files/streams.py writes a copy of elite-source.asm for each area, with the
\ other areas' lines blanked (build/elite-source-run.asm, -bank4.asm,
\ -cold.asm; the line numbers are the source's), and this file assembles
\ them one after the other, each at its own address. Every label is defined
\ once, in its own area's copy, and every block is assembled once; where a
\ routine lives on the other side (hot or cold), each copy holds the far-call
\ stub that reaches it, at the routine's place:
\
\   * the run: the configuration and the workspaces, then the main code from
\     CODE% in main RAM (saved as BCODE) to its split, below screen buffer 0
\     at &4000, continuing at &7400 after the quarter-square tables
\     (elite-qs.asm, &7000-&73FF) and running on into bank 4 at &8000
\     (main RAM from &7000 saved as HICODE);
\
\   * bank 4: the blocks that must be in bank 4, after the run;
\
\   * HAZEL: elite-data.asm's hot data (build/elite-data-hot.asm);
\
\   * the cold area, sideways RAM bank 7: elite-source.asm's cold blocks,
\     then elite-data.asm's (build/elite-data-cold.asm);
\
\ then the renderer (elite-gfx.asm).
\ elite-data.asm's blocks tagged BDATA, the dashboard image, are assembled on
\ their own (build/elite-data-bdata.asm, by the Makefile).
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-run.asm"

 ASSERT P% >= &8000     \ (the run's part from &7000 fills main RAM to &8000)

 PRINT "Quarter-square tables: &7000-", ~QS_RUN%-1, ", then the run from ", ~QS_RUN%, " to &7FFF"
 SAVE "3-assembled-output/HICODE.bin", &7000, &8000, &7000

\ ******************************************************************************
\
\ Port: the main code's part in bank 4 ends here; the rest of bank 4 is the
\ blocks of elite-source.asm tagged bank 4 (docs/memory-map.md)
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-bank4.asm"

.BANK4_END%

 PRINT "Bank 4: &8000-", ~BANK4_END%-1, " free ", &C000-BANK4_END%
 ASSERT BANK4_END% <= &C000
 SAVE "3-assembled-output/BANK4.bin", &8000, &C000, &8000

\ ******************************************************************************
\
\ Port: HAZEL (&C000-&DFFF), visible whatever bank is paged: the hot data,
\ elite-data.asm's blocks that are not tagged (build/elite-data-hot.asm,
\ which 2-build-files/streams.py writes) in the original's order from &C000: XX21,
\ E%, KWL%, KWH%, the blueprints from the missile's to the Dodo's, SNE and
\ ACT. DOSCLI stashes all of HAZEL in screen buffer 0 around each disc
\ command, so the data may sit anywhere in it; nothing the IRQ handler or
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

.HZ_END

 PRINT "HAZEL: game data &C000-", ~HZDATA_END%-1, ", free ", &DF00-HZ_END, " (+ 256 at &DF00, the MOS's)"
 ASSERT HZ_END <= &DF00  \ (&DF00-&DFFF is the MOS's: its FS numbers and
                        \ filing-system names, its lasting state)
 SAVE "3-assembled-output/HZDATA.bin", &C000, HZDATA_END%, &C000
 SAVE "3-assembled-output/HAZEL.bin", HZ_START, HZ_END, HZ_START

\ ******************************************************************************
\
\ Port: the cold area (docs/memory-map.md), paged in as ROMSEL = COLDBANK
\ (7): sideways RAM bank 7 from &8000, the original's cold code and data in
\ the original's order: the blocks of elite-source.asm tagged cold, with the
\ stubs that lead out of the cold area at their targets' places, then those
\ of elite-data.asm (QQ18 and the extended tokens TKN1, RUPLA, RUGAL and
\ RUTOK). Saved as COLD7.
\
\ ******************************************************************************

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-source-cold.asm"

 INCLUDE "3-assembled-output/elite-data-cold.asm"    \ QQ18 and the extended tokens

.COLD_END%

 PRINT "Bank 7 cold: &8000-", ~COLD_END%-1, " (the meridian window follows: elite-gfx.asm)"
 ASSERT COLD_END% <= &C000
 SAVE "3-assembled-output/COLD7.bin", &8000, COLD_END%, &8000

 PRINT "Addresses for the scramble routines in elite-checksum.py"
 PRINT "F% = ", ~F%
 PRINT "G% = ", ~G%
 PRINT "NA2% = ", ~NA2%

 INCLUDE "1-source-files/main-sources/elite-gfx.asm"      \ Port: the filled renderer (main RAM, banks 5 and 6,
                                  \ ANDY, and its meridian window in bank 7)
