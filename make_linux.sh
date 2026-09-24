#!/bin/bash
# make_linux.sh — build a self-contained OpenTyrian binary on Linux.
#
# SDL 1.2 and SDL_net 1.2 are built from source and linked STATICALLY.  A
# distro's libSDL is linked against whatever that distro has (or is
# sdl12-compat, which needs SDL2), and bundling it drags every one of those in
# as a hard dependency on the user's machine.  SDL built from source instead
# loads its X11, ALSA and PulseAudio backends with dlopen at run time, so the
# resulting binary needs nothing beyond glibc and libm.
#
# The freeware Tyrian 2.1 data is fetched into ./data if missing.
#
# Build requirements (headers only; nothing is linked from them):
#   Debian/Ubuntu:  sudo apt install build-essential pkg-config curl unzip autotools-dev \
#       libasound2-dev libpulse-dev libx11-dev libxext-dev libxrandr-dev \
#       libxrender-dev
#
# Usage: ./make_linux.sh [data-dir]     (default: ./data, fetched if missing)
set -euo pipefail

cd "$(dirname "$0")"
DATA_ARG="${1:-data}"

have_data() { find "$1" -maxdepth 1 -iname "tyrian1.lvl" 2>/dev/null | grep -q .; }

if ! have_data "$DATA_ARG" && [ "$#" -ge 1 ]; then
    echo "ERROR: no Tyrian data in '$DATA_ARG'" >&2
    echo "Point make_linux.sh at your Tyrian 2.1 data, or run it with no argument" >&2
    echo "to download the freeware release into ./data automatically." >&2
    exit 1
fi
./get_data.sh "$DATA_ARG"
DATA_DIR="$(cd "$DATA_ARG" && pwd)"

# ---- static SDL 1.2 + SDL_net 1.2 from source, installed under build/sdl ----
SDL_REV="d2af6eedb556c783047e1c7475cf8bbefaf8e56b"
SDL_NET_VER="1.2.8"
PREFIX="$PWD/build/sdl"
NPROC="$(nproc 2>/dev/null || echo 4)"

# The license of anything we link in has to travel with the binary.  Keep the
# copies inside the prefix, since that is what CI caches: on a cache hit the
# source trees below are never unpacked.
install_license() {  # $1 = source directory, $2 = name in the package
    mkdir -p "$PREFIX/share/licenses"
    for name in LICENSE.txt LICENSE COPYING.txt COPYING; do
        if [ -f "$1/$name" ]; then
            cp "$1/$name" "$PREFIX/share/licenses/$2.txt"
            return 0
        fi
    done
    echo "ERROR: no license file found in $1" >&2
    exit 1
}

# The bundled config.guess/config.sub predate aarch64.
update_config_scripts() {  # $1 = source directory
    find "$1" -name config.guess -exec cp /usr/share/misc/config.guess {} \;
    find "$1" -name config.sub -exec cp /usr/share/misc/config.sub {} \;
}

if [ ! -f "$PREFIX/lib/libSDL.a" ]; then
    echo "Building SDL 1.2 ($SDL_REV, static) ..."
    mkdir -p build/vendor
    curl -fL --progress-bar -o build/vendor/SDL.tar.gz \
        "https://github.com/libsdl-org/SDL-1.2/archive/$SDL_REV.tar.gz"
    rm -rf "build/vendor/SDL-1.2-$SDL_REV"
    tar -xzf build/vendor/SDL.tar.gz -C build/vendor
    update_config_scripts "build/vendor/SDL-1.2-$SDL_REV"
    (cd "build/vendor/SDL-1.2-$SDL_REV" &&
        ./configure --prefix="$PREFIX" --disable-shared --enable-static \
            --disable-esd --disable-arts --disable-nas --disable-video-directfb \
            --disable-video-aalib --disable-video-caca >/dev/null &&
        make -j"$NPROC" >/dev/null &&
        make install >/dev/null)
    install_license "build/vendor/SDL-1.2-$SDL_REV" SDL
fi

if [ ! -f "$PREFIX/lib/libSDL_net.a" ]; then
    echo "Building SDL_net $SDL_NET_VER (static) ..."
    mkdir -p build/vendor
    curl -fL --progress-bar -o build/vendor/SDL_net.tar.gz \
        "https://github.com/libsdl-org/SDL_net/archive/refs/tags/release-$SDL_NET_VER.tar.gz"
    rm -rf "build/vendor/SDL_net-release-$SDL_NET_VER"
    tar -xzf build/vendor/SDL_net.tar.gz -C build/vendor
    update_config_scripts "build/vendor/SDL_net-release-$SDL_NET_VER"
    (cd "build/vendor/SDL_net-release-$SDL_NET_VER" &&
        PATH="$PREFIX/bin:$PATH" ./configure --prefix="$PREFIX" \
            --disable-shared --enable-static --disable-gui >/dev/null &&
        make -j"$NPROC" >/dev/null &&
        make install >/dev/null)
    install_license "build/vendor/SDL_net-release-$SDL_NET_VER" SDL_net
fi

# ---- the game, against the static SDL ----
# pkg-config resolves sdl/SDL_net from our prefix; --static pulls in the
# libraries SDL itself needs (m, dl, pthread, rt) for the static link.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
make clean >/dev/null
make -j"$NPROC" \
    SDL_LDFLAGS="-L$PREFIX/lib" \
    SDL_LDLIBS="$(pkg-config --static --libs-only-l sdl SDL_net)"

echo
if ldd opentyrian | grep -q "libSDL"; then
    echo "ERROR: opentyrian still links SDL dynamically" >&2
    exit 1
fi
echo "built: ./opentyrian (SDL linked statically)"
echo "run:   ./opentyrian --data=\"$DATA_DIR\""
