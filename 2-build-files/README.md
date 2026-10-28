# Build files for the BBC Master version of Elite

This folder contains support scripts for building the BBC Master version of Elite.

* [crc32.py](crc32.py) calculates checksums during the verify stage and compares the results with the relevant binaries in the [4-reference-binaries](../4-reference-binaries) folder

* [elite-checksum.py](elite-checksum.py) adds checksums and encryption to the assembled output

* [elite-decrypt.py](elite-decrypt.py) decrypts an encrypted game binary by doing the opposite to the elite-checksum.py script (this is not used in the build process, but is useful when trying to decrypt any new releases that might be found)

It also contains the `make.exe` executable for Windows, plus the required DLL files.

---

Right on, Commanders!

_Mark Moxon_
## Added for Solid Elite

* [faces.py](faces.py), [lightramps.py](lightramps.py), [lightcheck.py](lightcheck.py), [hangarcols.py](hangarcols.py), [hangarinks.py](hangarinks.py) and [flare.py](flare.py) generate and check the renderer's tables, and [flarevis.py](flarevis.py) renders the lens flare's probe dumps (see [docs/renderer.md](../docs/renderer.md)); [dashboard.py](dashboard.py) (with [swatch35.py](swatch35.py), the dither cells), [streams.py](streams.py) (the three passes, the flow and the stubs), [lightpass.py](lightpass.py) (the lighting's two passes), [layout-info.py](layout-info.py) and [bankcheck.py](bankcheck.py) (the banking rules) run in the build (see [docs/memory-map.md](../docs/memory-map.md)).

* [hooks/pre-commit](hooks/pre-commit) refuses a commit whose `solid-elite-bbc-master.ssd` (the disc in the repository's root, which `make` copies from `5-compiled-game-discs`) is not the build's disc. Install it with `git config core.hooksPath 2-build-files/hooks`.
