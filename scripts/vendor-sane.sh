#!/bin/zsh
# Vendor SANE (scanimage + libsane + all backends + deps) from the local
# Homebrew install into Vendor/sane/, relocating every Mach-O from
# absolute /opt/homebrew install names to @rpath so the tree works from
# inside PaperDrop.app.
#
#   scripts/vendor-sane.sh            # vendor (requires brew sane-backends)
#   scripts/vendor-sane.sh --verify   # assert every library reference
#                                     # resolves inside the vendored tree
set -e
cd "$(dirname "$0")/.."

VENDOR=Vendor/sane
BREW_SANE=/opt/homebrew/opt/sane-backends

# Single home for "every vendored Mach-O" — used by verify and signing.
machos() {
    echo $VENDOR/bin/scanimage $VENDOR/lib/*.dylib $VENDOR/lib/sane/*.so
}

# Linked libraries of a Mach-O (its own install name included, for dylibs).
linked() {
    otool -L "$1" | tail -n +2 | awk '{print $1}'
}

if [[ "$1" == "--verify" ]]; then
    # Every rpath in the tree resolves to the dylib directory (see the
    # relocate calls below), so each @rpath/X must exist as lib/X.
    bad=0
    for f in $(machos); do
        for dep in $(linked "$f"); do
            case $dep in
                /opt/homebrew/*)
                    echo "UNRELOCATED: $f -> $dep"
                    bad=1
                    ;;
                @rpath/*)
                    if [[ ! -e $VENDOR/lib/${dep#@rpath/} ]]; then
                        echo "MISSING: $f -> $dep"
                        bad=1
                    fi
                    ;;
            esac
        done
    done
    [[ $bad == 0 ]] && echo "vendor tree clean: every library reference resolves"
    exit $bad
fi

[[ -d "$BREW_SANE" ]] || { echo "brew install sane-backends first" >&2; exit 1; }

rm -rf $VENDOR
mkdir -p $VENDOR/bin $VENDOR/lib/sane $VENDOR/etc $VENDOR/licenses

# --- Copy (dereference symlinks; skip backend symlink aliases) ---
BACKENDS=("$BREW_SANE"/lib/sane/*.so(^@))
cp "$BREW_SANE/bin/scanimage" $VENDOR/bin/
cp "$BREW_SANE/lib/libsane.1.dylib" $VENDOR/lib/
cp $BACKENDS $VENDOR/lib/sane/
# Dependencies: the transitive closure of Homebrew dylibs the copied
# binaries link, read from otool rather than listed by hand — Homebrew
# renames them on major bumps and adds new ones (libtiff now pulls in
# webp), and backends bring their own (magicolor needs net-snmp, which
# needs OpenSSL's libcrypto). Walks the Homebrew originals so an @rpath
# reference resolves beside the library making it.
typeset -A have
have[libsane.1.dylib]=1
queue=("$BREW_SANE/bin/scanimage" "$BREW_SANE/lib/libsane.1.dylib" $BACKENDS)
while (( ${#queue} )); do
    f=${queue[1]}
    shift queue
    for dep in $(linked "$f"); do
        case $dep in
            /opt/homebrew/*) src=$dep ;;
            @rpath/*)
                src=${f:h}/${dep#@rpath/}
                [[ -e $src ]] || src=/opt/homebrew/lib/${dep#@rpath/}
                ;;
            *) continue ;;
        esac
        name=${src:t}
        [[ -n ${have[$name]} ]] && continue
        [[ -e $src ]] || { echo "cannot resolve $dep (linked by $f)" >&2; exit 1; }
        have[$name]=1
        cp "$src" $VENDOR/lib/
        queue+=("$src")
    done
done
cp -RL /opt/homebrew/etc/sane.d $VENDOR/etc/
cp "$BREW_SANE"/{COPYING,LICENSE} $VENDOR/licenses/
brew list --versions sane-backends > $VENDOR/VERSION

chmod -R u+w $VENDOR

# --- Relocate: absolute /opt/homebrew install names -> @rpath ---
# One install_name_tool invocation per file: -change pairs for every
# non-system dep, plus the file's -id/-add_rpath, batched together
# (each invocation rewrites the whole binary).
relocate() {
    local f=$1
    shift
    local -a extra_args=("$@")
    local -a changes=()
    for dep in $(linked "$f" | grep "^/opt/homebrew"); do
        changes+=(-change "$dep" "@rpath/$(basename "$dep")")
    done
    [[ ${#changes} -eq 0 && ${#extra_args} -eq 0 ]] && return 0
    install_name_tool "${changes[@]}" "${extra_args[@]}" "$f" 2>/dev/null
}

for dylib in $VENDOR/lib/*.dylib; do
    # siblings live in the same dir (Contents/Frameworks)
    relocate "$dylib" -id "@rpath/$(basename "$dylib")" -add_rpath "@loader_path"
done
for so in $VENDOR/lib/sane/*.so; do
    # backends live one level below the dylibs (Frameworks/sane)
    relocate "$so" -add_rpath "@loader_path/.."
done
# scanimage is installed at Contents/Helpers; dylibs at Contents/Frameworks
relocate $VENDOR/bin/scanimage -add_rpath "@executable_path/../Frameworks"

# install_name_tool invalidates signatures; ad-hoc re-sign so the tree is
# runnable locally. bundle.sh force-re-signs with the real identity.
codesign --force --sign - $(machos) 2>/dev/null

echo "vendored SANE $(cat $VENDOR/VERSION) into $VENDOR ($(du -sh $VENDOR | cut -f1))"
