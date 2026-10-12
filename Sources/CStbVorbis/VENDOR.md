# stb_vorbis (vendored)

- Upstream: https://github.com/nothings/stb, file `stb_vorbis.c` v1.22
- Commit: 2c980bb59875b0d32144a71867fbdebb2f77cd20 (2026-08-01)
- License: public domain or MIT at your choice; see `LICENSE` (the upstream repo's file)
- Local changes: none. `include/stb_vorbis.h` is our shim that includes the
  upstream file in header-only mode so Swift can import it; it is not upstream.
- To update: replace `stb_vorbis.c` with the new upstream file, then update
  the version and commit above.
