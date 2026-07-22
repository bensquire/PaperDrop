#!/bin/zsh
# Vendor SANE (scanimage + libsane + all backends + deps) from the local
# Homebrew install into Vendor/sane/, relocating every Mach-O from
# absolute /opt/homebrew install names to @rpath so the tree works from
# inside PaperDrop.app.
#
#   scripts/vendor-sane.sh            # vendor (requires brew sane-backends)
#   scripts/vendor-sane.sh --verify   # assert no /opt/homebrew references
set -e
cd "$(dirname "$0")/.."

VENDOR=Vendor/sane
BREW_SANE=/opt/homebrew/opt/sane-backends

if [[ "$1" == "--verify" ]]; then
    bad=0
    for f in $VENDOR/bin/scanimage $VENDOR/lib/*.dylib $VENDOR/lib/sane/*.so; do
        if otool -L "$f" | tail -n +2 | grep -q "/opt/homebrew"; then
            echo "UNRELOCATED: $f"
            bad=1
        fi
    done
    [[ $bad == 0 ]] && echo "vendor tree clean: no /opt/homebrew references"
    exit $bad
fi

[[ -d "$BREW_SANE" ]] || { echo "brew install sane-backends first" >&2; exit 1; }

rm -rf $VENDOR
mkdir -p $VENDOR/bin $VENDOR/lib/sane $VENDOR/etc $VENDOR/licenses

# --- Copy (dereference symlinks; skip backend symlink aliases) ---
cp "$BREW_SANE/bin/scanimage" $VENDOR/bin/
cp "$BREW_SANE/lib/libsane.1.dylib" $VENDOR/lib/
for so in "$BREW_SANE"/lib/sane/*.so; do
    [[ -L "$so" ]] && continue
    cp "$so" $VENDOR/lib/sane/
done
DEPS=(
    /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib
    /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib
    /opt/homebrew/opt/libpng/lib/libpng16.16.dylib
    /opt/homebrew/opt/libtiff/lib/libtiff.6.dylib
    /opt/homebrew/opt/zstd/lib/libzstd.1.dylib
    /opt/homebrew/opt/xz/lib/liblzma.5.dylib
)
for dep in $DEPS; do
    cp "$dep" $VENDOR/lib/
done
cp -RL /opt/homebrew/etc/sane.d $VENDOR/etc/
cp "$BREW_SANE"/{COPYING,LICENSE} $VENDOR/licenses/
brew list --versions sane-backends > $VENDOR/VERSION

chmod -R u+w $VENDOR

# --- Relocate: absolute /opt/homebrew install names -> @rpath ---
relocate() {
    local f=$1
    # rewrite each non-system dependency reference
    otool -L "$f" | tail -n +2 | awk '{print $1}' | grep "^/opt/homebrew" \
    | while read -r dep; do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null
    done
}

for dylib in $VENDOR/lib/*.dylib; do
    install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib" 2>/dev/null
    relocate "$dylib"
    # siblings live in the same dir (Contents/Frameworks)
    install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done
for so in $VENDOR/lib/sane/*.so; do
    relocate "$so"
    # backends live one level below the dylibs (Frameworks/sane)
    install_name_tool -add_rpath "@loader_path/.." "$so" 2>/dev/null || true
done
relocate $VENDOR/bin/scanimage
# scanimage is installed at Contents/Helpers; dylibs at Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" $VENDOR/bin/scanimage

# install_name_tool invalidates signatures; ad-hoc re-sign so the tree is
# runnable locally. bundle.sh force-re-signs with the real identity.
for f in $VENDOR/bin/scanimage $VENDOR/lib/*.dylib $VENDOR/lib/sane/*.so; do
    codesign --force --sign - "$f" 2>/dev/null
done

echo "vendored SANE $(cat $VENDOR/VERSION) into $VENDOR ($(du -sh $VENDOR | cut -f1))"
