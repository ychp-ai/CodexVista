# Zstandard decoder

Vendored from [facebook/zstd v1.5.7](https://github.com/facebook/zstd/tree/v1.5.7),
using the BSD license in `Zstd-LICENSE` (also bundled in the app).
Only the upstream single-file decompressor is compiled, with no legacy formats,
assembly, compressor, process execution, or runtime downloads. Xcode compiles the
C source for both arm64 and x86_64. Swift imports the public headers through CZstd.
The source adds approximately 1.1 MiB to the repository; compiled size depends on
configuration and dead stripping. No user data leaves the process.

Source archive: https://codeload.github.com/facebook/zstd/tar.gz/refs/tags/v1.5.7

SHA-256:

- Archive: `37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3`
- Generated `zstddeclib.c`: `5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`
- `zstd.h`: `9b4bc8245565c98ccfc61c07749928b57e7c0f6fddb0530c4f6aa1971893d88b`

To update, review the upstream release/security notes, obtain the tagged source,
and run from its `build/single_file_libs` directory:

```sh
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

Copy the generated file, `lib/zstd.h`, `lib/zstd_errors.h`, and root `LICENSE`
(renamed `Zstd-LICENSE`) here; record the version and hashes. Keep upstream source
unaltered. Run the full XCTest suite and a Universal build. Decoder window memory
is limited to 128 MiB by `RolloutByteStream`; callers retain their own decoded-data
limits. Decoder errors expose no source bytes.

Dependency review on 2026-10-26: DepTrust does not support this vendored C library
(the CocoaPods lookup found no package; OSS-Fuzz is an unsupported ecosystem).
The upstream GitHub security page listed no published advisories. This is not a
claim that the library has no vulnerabilities; review upstream advisories on updates.
