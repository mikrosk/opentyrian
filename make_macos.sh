#!/bin/bash
# make_macos.sh — build a self-contained, universal OpenTyrian.app (macOS).
# SDL 1.2 comes from sdl12-compat, which runs on top of the official
# SDL2.framework; both are bundled together with the freeware Tyrian 2.1
# data, so the app runs on any Mac with nothing installed.
#
# Usage: ./make_macos.sh [data-dir]     (default: ./data, fetched if missing)
set -euo pipefail

cd "$(dirname "$0")"
DATA_ARG="${1:-data}"

have_data() { find "$1" -maxdepth 1 -iname "tyrian1.lvl" 2>/dev/null | grep -q .; }

if ! have_data "$DATA_ARG" && [ "$#" -ge 1 ]; then
    echo "ERROR: no Tyrian data in '$DATA_ARG'" >&2
    echo "Point make_macos.sh at your Tyrian 2.1 data, or run it with no argument" >&2
    echo "to download the freeware release into ./data automatically." >&2
    exit 1
fi
./get_data.sh "$DATA_ARG"
DATA_DIR="$(cd "$DATA_ARG" && pwd)"

OUT="build/OpenTyrian.app"

# ---- official universal SDL2.framework (arm64 + x86_64), cached ----
SDL2_VER="2.32.10"
FW="$PWD/build/vendor/SDL2.framework"
if [ ! -d "$FW" ]; then
    echo "Downloading SDL2 $SDL2_VER framework (universal, ~2 MB) ..."
    mkdir -p build/vendor
    curl -fL --progress-bar -o build/vendor/SDL2.dmg \
        "https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VER/SDL2-$SDL2_VER.dmg"
    MNT=$(mktemp -d)
    hdiutil attach build/vendor/SDL2.dmg -nobrowse -quiet -mountpoint "$MNT"
    cp -R "$MNT/SDL2.framework" build/vendor/
    hdiutil detach "$MNT" -quiet
    rm build/vendor/SDL2.dmg
fi

# ---- sdl12-compat (universal), installed under build/sdl ----
SDL12_COMPAT_VER="1.2.76"
PREFIX="$PWD/build/sdl"
if [ ! -f "$PREFIX/lib/libSDL-1.2.0.dylib" ]; then
    echo "Building sdl12-compat $SDL12_COMPAT_VER (universal) ..."
    mkdir -p build/vendor
    curl -fL --progress-bar -o build/vendor/sdl12-compat.tar.gz \
        "https://github.com/libsdl-org/sdl12-compat/archive/refs/tags/release-$SDL12_COMPAT_VER.tar.gz"
    SRC="build/vendor/sdl12-compat-release-$SDL12_COMPAT_VER"
    rm -rf "$SRC"
    tar -xzf build/vendor/sdl12-compat.tar.gz -C build/vendor
    cmake -S "$SRC" -B "$SRC/build" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13 \
        -DSDL2_INCLUDE_DIRS="$FW/Headers" -DSDL12TESTS=OFF >/dev/null
    cmake --build "$SRC/build" -j"$(sysctl -n hw.ncpu)" >/dev/null
    cmake --install "$SRC/build" >/dev/null
    install_name_tool -id @rpath/libSDL-1.2.0.dylib "$PREFIX/lib/libSDL-1.2.0.dylib"
    mkdir -p "$PREFIX/share/licenses"
    cp "$SRC/LICENSE.txt" "$PREFIX/share/licenses/sdl12-compat.txt"
fi

# ---- one build per architecture, then lipo them together ----
# The Makefile's SDL_* variables normally come from pkg-config; overriding
# them on the command line points the build at sdl12-compat instead.
# Networking is off: the release has no SDL_net to bundle.
build_arch() {  # $1 = arm64 | x86_64
    make clean >/dev/null
    make -j"$(sysctl -n hw.ncpu)" \
        CC="cc -arch $1 -mmacosx-version-min=10.13" \
        WITH_NETWORK=false \
        SDL_CPPFLAGS="-I$PREFIX/include/SDL" \
        SDL_LDFLAGS="-L$PREFIX/lib -Wl,-rpath,@executable_path/../Frameworks" \
        SDL_LDLIBS="-lSDLmain -lSDL -framework Cocoa" >/dev/null
    mv opentyrian "build/opentyrian-$1"
}
mkdir -p build
build_arch arm64
build_arch x86_64
lipo -create -output build/opentyrian-universal build/opentyrian-arm64 build/opentyrian-x86_64

# ---- assemble the bundle ----
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Frameworks"

VERSION="$( (git describe --tags || git rev-parse --short HEAD) 2>/dev/null || echo dev)"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>opentyrian</string>
    <key>CFBundleIdentifier</key>      <string>io.github.opentyrian.OpenTyrian</string>
    <key>CFBundleName</key>            <string>OpenTyrian</string>
    <key>CFBundleDisplayName</key>     <string>OpenTyrian</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleIconFile</key>        <string>OpenTyrian</string>
    <key>LSMinimumSystemVersion</key>  <string>10.13</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# The game looks for "data" in the current directory, so the bundle starts it
# from Resources.
cp build/opentyrian-universal "$OUT/Contents/MacOS/opentyrian-bin"
cat > "$OUT/Contents/MacOS/opentyrian" <<'LAUNCHER'
#!/bin/sh
cd "$(dirname "$0")/../Resources" && exec ../MacOS/opentyrian-bin "$@"
LAUNCHER
chmod +x "$OUT/Contents/MacOS/opentyrian"

cp "$PREFIX/lib/libSDL-1.2.0.dylib" "$OUT/Contents/Frameworks/"

# SDL2.framework, headers stripped
cp -R "$FW" "$OUT/Contents/Frameworks/"
rm -rf "$OUT/Contents/Frameworks/SDL2.framework/Headers" \
       "$OUT/Contents/Frameworks/SDL2.framework/Versions/A/Headers"

# Game data: the engine looks in <bundle>/Contents/Resources/data (lowercase names)
mkdir -p "$OUT/Contents/Resources/data"
find "$DATA_DIR" -maxdepth 1 -type f | while read -r f; do
    cp "$f" "$OUT/Contents/Resources/data/$(basename "$f" | tr '[:upper:]' '[:lower:]')"
done

# Licenses.  SDL2's travels inside the framework already, but three levels
# down where nobody would look for it.
cp COPYING "$OUT/Contents/Resources/COPYING.txt"
mkdir -p "$OUT/Contents/Resources/licenses"
cp "$FW/Versions/A/Resources/License.txt" "$OUT/Contents/Resources/licenses/SDL2.txt"
cp "$PREFIX/share/licenses/sdl12-compat.txt" "$OUT/Contents/Resources/licenses/"
cp doc/tyrian-freeware-license.txt "$OUT/Contents/Resources/licenses/Tyrian.txt"

# App icon from the 128px Linux icon
python3 make_icon.py linux/icons/tyrian-128.png "$OUT/Contents/Resources/OpenTyrian.icns" \
    && echo "icon: from linux/icons/tyrian-128.png" || echo "note: icon generation failed, skipping"

codesign --force -s - "$OUT/Contents/Frameworks/SDL2.framework"
codesign --force -s - "$OUT/Contents/Frameworks/libSDL-1.2.0.dylib"
codesign --force -s - "$OUT/Contents/MacOS/opentyrian-bin"
codesign --force -s - "$OUT"
touch "$OUT"
echo "built: $OUT"
