# libxmp-lite (vendored subset)

- Upstream: https://github.com/libxmp/libxmp, tag `libxmp-4.7.4`,
  commit 5d4f6aa2c7dcdf8e9cd8129fe579d45b36a302da (2026-10-10)
- What is here: the libxmp-lite subset (MOD, S3M, XM and IT modules) exactly
  as listed in upstream `lite/src/Makefile` and `lite/src/loaders/Makefile`,
  plus the public header `include/xmp.h`. Nothing else from the repository.
- Build defines: `LIBXMP_CORE_PLAYER` and `LIBXMP_STATIC`, set in
  `Package.swift`. `common.h` turns off the depackers and ProWizard itself.
- License: MIT; see `LICENSE` (upstream `docs/COPYING`).
- Local changes: none.
- To update: copy the same file lists from the new tag, then update the tag
  and commit above.
