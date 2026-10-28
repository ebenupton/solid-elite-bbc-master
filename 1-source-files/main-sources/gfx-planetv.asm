\ ******************************************************************************
\
\ gfx-planetv.asm - the planet's detail's variables that the frame layer
\ reads: in the renderer's shared workspace (main RAM below &3000,
\ elite-gfx.asm), where both the meridian window (bank 7, which writes them
\ in game context) and the frame layer (bank 6, with ACCCON X either way)
\ see them. Variables only: F_INIT clears MN_ON, and f_reset after
\ every frame
\
\ ******************************************************************************

\ The moon, for the frame layer (pf_moon, gfx-planet7.asm; f_moon, bank 6)
.MN_ON  SKIP 1          \ bit 7: a moon this frame; 6: behind the planet; 5:
                        \ behind the sun
.MN_X   SKIP 2          \ its centre, radius and z (16 bits, &FFFF if further)
.MN_Y   SKIP 2
.MN_R   SKIP 1
.MN_Z   SKIP 2
.MN_N   SKIP 1          \ its crater's slots: PCMAX .. MN_N - 1
.MN_INV SKIP 1

\ The moon as each buffer last showed it (f_moon, f_moon0: gfx-frame.asm),
\ by buffer
.MO_ON  SKIP 2          \ bit 7: drawn; bits 6 and 5: MN_ON's then
.MO_XL  SKIP 2          \ its centre
.MO_XH  SKIP 2
.MO_YL  SKIP 2
.MO_YH  SKIP 2
.MO_R   SKIP 2          \ its radius
.MO_T   SKIP 2          \ its rows (none: T > B)
.MO_B   SKIP 2
.MO_CT  SKIP 2          \ its crater's rows (none: 255, 0)
.MO_CB  SKIP 2
