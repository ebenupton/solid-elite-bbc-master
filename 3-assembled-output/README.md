# Assembled output for the BBC Master version of Elite

This folder contains the output binaries from the build process for the BBC Master version of Elite. In the port (see [docs/README.md](../docs/README.md)) these are BCODE (the main code in main RAM), HICODE (main RAM &7000-&7FFF), BANK4 (Elite's home bank), COLD7 (the cold area, bank 7), HAZEL (the game data), BANK5, RASTA and BANK6 (the renderer), BDATA (the dashboard image) and M128Elt (the loader); HZDATA is the game data on its own, for the harness. The generated sources that the build assembles (the per-area copies of the source, the dashboard's tables) are written here too, and are not tracked.

It also contains [compile.txt](compile.txt), which contains the output from the assembly process. This is very useful when debugging the build process.

---

Right on, Commanders!

_Mark Moxon_