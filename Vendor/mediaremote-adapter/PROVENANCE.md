# MediaRemote Adapter

Source: https://github.com/ungive/mediaremote-adapter
Revision: 73f14ab1568371e6e3c44063f21c34c5e2712c4d
License: BSD-3-Clause (see LICENSE)

The bin/, include/, and src/ directories are vendored unchanged. Arc compiles the
helper from source using Apple's clang; no prebuilt binary is downloaded.
The helper is loaded by /usr/bin/perl, never linked into Arc.
