\ ******************************************************************************
\
\ sunref.asm - the port's sun-parking routines, assembled for the released
\ SNG47, as the harness's patch to the reference (sunref.py, which writes
\ 3-assembled-output/sunref-syms.asm, binding every name the routines use to SNG47's
\ address for it, and assembles this with PASSIVE 0 and 1)
\
\ The routines are elite-source.asm's blocks tagged "Area: ..., again", in
\ the second emission that streams.py writes (3-assembled-output/elite-source-again.asm:
\ their labels, and the targets of their JSRs and JMPs, named A_<name>).
\ The parked sun, SUNPK and SUNPF, follows them, then the space station's
\ line heap, SR_HEAP, which the patch moves there from LSO (the sun's), all
\ in SNG47's unused &0B9D-&0CFF (sunref.py: FREE).
\
\ PASSIVE = 1: the passive variant, whose part 14 and TT110 sites call the
\ original's WPLS and NWSPS (P_SUNUP, P_SUNLAU), so that the sun is never
\ parked: it must run exactly as the original (sunref.py, "The proofs").
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/sunref-syms.asm"

 ORG SR_ORG

.SR_START

 INCLUDE "3-assembled-output/elite-source-again.asm"

IF PASSIVE

.P_SUNUP

 JMP A_WPLS

.P_SUNLAU

 JMP A_NWSPS

ENDIF

.SUNPK

 SKIP NI%

.SUNPF

 EQUB 0

.SR_END

.SR_HEAP                \ the space station's line heap, at most 101 bytes (the
                        \ Dodo's: 4 * 25 + 1)

 ASSERT SR_HEAP + 101 <= &0D00

 SAVE "3-assembled-output/sunref.bin", SR_START, SR_END
