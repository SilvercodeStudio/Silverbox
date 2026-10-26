// Silverbox shim, not an upstream file: exposes the declarations of the vendored
// stb_vorbis.c (which is both header and implementation) as a module header.
#ifndef SILVERBOX_STB_VORBIS_SHIM_H
#define SILVERBOX_STB_VORBIS_SHIM_H
#define STB_VORBIS_HEADER_ONLY
#include "../stb_vorbis.c"
#undef STB_VORBIS_HEADER_ONLY
#endif
