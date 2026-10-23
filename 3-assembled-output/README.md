# Assembled output for the BBC Master version of Elite

This folder contains the output binaries from the build process for the BBC Master version of Elite. In the port (see [docs/memory-map.md](../docs/memory-map.md)) these are BCODE (main RAM from &1E24: the glue area, the low pass and the hot pass's first container), HICODE (main RAM &7000-&7FFF: the quarter-square tables and the hot pass's second container), BANK4 (Elite's home bank: the rest of the hot pass, then the hot data that HAZEL has no room for), COLD7 (the cold pass, bank 7), HAZEL (the game data), BANK5, RASTA, BANK6 and MERID (the renderer: the rasteriser, its polygon window in ANDY, the frame layer, and the meridian window in bank 7), BDATA (the dashboard image, which DIALS1 holds before it is assembled) and M128Elt (the loader); HZDATA is the game data on its own, for 2-build-files/faces.py. The generated sources that the build assembles (the copies of the source for each pass and container, the stubs, the dashboard's tables) and its reports (symbols.txt, banks.txt, flow.txt, direct.txt) are written here too, and are not tracked.

It also contains [compile.txt](compile.txt), which contains the output from the assembly process. This is very useful when debugging the build process.

---

Right on, Commanders!

_Mark Moxon_