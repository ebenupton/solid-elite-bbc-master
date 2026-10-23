# Annotated source code for the BBC Master version of Elite

This folder contains the annotated source code for the BBC Master version of Elite.

* Main source files:

  * [elite-source.asm](elite-source.asm) contains the main source for the game

  * [elite-data.asm](elite-data.asm) contains source for the game data, including the game text and ship blueprints

* Other source files:

  * [elite-loader.asm](elite-loader.asm) contains the source for the loader

  * [elite-disc.asm](elite-disc.asm) builds the SSD disc image from the assembled binaries and other source files

  * [elite-readme.asm](elite-readme.asm) generates a README file for inclusion on the SSD disc image

* Files that are generated during the build process:

  * [elite-build-options.asm](elite-build-options.asm) stores the make options in BeebAsm format so they can be included in the assembly process

---

Right on, Commanders!

_Mark Moxon_

## Added for Solid Elite

The port's own sources (see [docs/memory-map.md](../../docs/memory-map.md) and [docs/renderer.md](../../docs/renderer.md)):

* [elite-layout.asm](elite-layout.asm) is the file the Makefile assembles: it places the configuration, the glue area, the low, hot and cold passes and the renderer, each at its own address; [elite-measure.asm](elite-measure.asm) assembles the hot pass once to measure each block's size for the flow

* [elite-glue.asm](elite-glue.asm) is the glue area, the port's own code below &3000, with [elite-stubs.asm](elite-stubs.asm), the stubs between the hot and cold passes

* [elite-qs.asm](elite-qs.asm) holds the quarter-square multiplication tables

* [elite-gfx.asm](elite-gfx.asm) and the `gfx-*.asm` files are the filled renderer: its shared workspace, the rasteriser (`gfx-raster*.asm`), the frame layer (`gfx-frame*.asm`, `gfx-faces.asm`, `gfx-light*.asm`, `gfx-flare*.asm`, `gfx-hangar*.asm`), the meridian window for the beach ball (`gfx-merid.asm`), the kept solid rows (`gfx-raster_kept.asm`, `gfx-kept7.asm`) and the glue and hooks in Elite's code (`gfx-gvars.asm`, `gfx-tramp.asm`, `gfx-gluehooks.asm`, `gfx-gstubs.asm`, `gfx-hooks.asm`)
