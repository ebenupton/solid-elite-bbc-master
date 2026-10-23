\ ******************************************************************************
\
\ elite-measure.asm - the measure of the hot pass (docs/memory-map.md)
\
\ Port: the Makefile assembles this before elite-layout.asm, only for its symbols
\ (3-assembled-output/measure-symbols.txt), from which 2-build-files/streams.py takes the size of
\ each block of the hot pass and of the hot data, to flow them through their
\ containers. It assembles what elite-layout.asm does, but with the whole
\ hot pass in one copy (3-assembled-output/elite-source-measure.asm, a label FLOW_<n> at
\ the start of each block, FLOW_END after the last) from the low pass's end
\ onwards, past the containers' limits, and the whole hot data in one copy
\ (3-assembled-output/elite-data-measure.asm, DFLOW_<n> and DFLOW_END) at &C000. A
\ block's size is the same wherever it goes (no block of either aligns
\ itself, and a stub at a routine's place is the same size in every
\ container), so the sizes measured here are the sizes in the layout. It
\ also gives the containers' starts: LOW_END% (the glue area and the low
\ pass are assembled as in the layout) and QS_RUN% (after the quarter-square
\ tables). Nothing it saves is used: elite-layout.asm saves every image
\ afterwards.
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-config.asm"

 ORG CODE%

 INCLUDE "1-source-files/main-sources/elite-glue.asm"

.GLUE_END%

 INCLUDE "3-assembled-output/elite-source-low.asm"

.LOW_END%

 CLEAR &7000, &C000
 ORG &7000

 INCLUDE "1-source-files/main-sources/elite-qs.asm"

.QS_RUN%

 CLEAR LOW_END%, &C000
 ORG LOW_END%

 INCLUDE "3-assembled-output/elite-source-measure.asm"

.FLOW_END

.HOT3_END%

.BANK4_END%

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-source-cold.asm"

 INCLUDE "3-assembled-output/elite-data-cold.asm"

.COLD_END%

 CLEAR &C000, &FF00
 ORG &C000

.HZ_START

 INCLUDE "3-assembled-output/elite-data-measure.asm"

.DFLOW_END

.HZDATA_END%

.HZ_END

 INCLUDE "1-source-files/main-sources/elite-gfx.asm"
