#!/usr/bin/env bash
# Build the executables: one self-contained file each (the project is packed
# into the binary), zipped under build/.
#
#   tools/build.sh            both
#   tools/build.sh windows    build/WestVirginia_windows.zip
#   tools/build.sh linux      build/WestVirginia_linux.zip
#
# Needs the Godot editor this project was made with (4.7-dev5; `GODOT` names
# another binary) and its export templates, which this fetches if they are
# missing: only the two files wanted, not the 1.2 GB archive.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
WHAT="${1:-both}"
VER="$("$GODOT" --version 2>/dev/null | tail -1 | sed 's/\.official.*//')"
TEMPLATES="$HOME/.local/share/godot/export_templates/$VER"

build() {
	local preset="$1" dir="$2" file="$3" template="$4"
	[ -f "$TEMPLATES/$template" ] || python3 tools/fetch_export_template.py "$template"
	rm -rf "build/$dir"
	mkdir -p "build/$dir"
	"$GODOT" --headless --path . --export-release "$preset" "build/$dir/$file"
	[ -s "build/$dir/$file" ] || { echo "no build/$dir/$file: the export failed" >&2; exit 1; }
	cp README.md "build/$dir/README.txt"
	rm -f "build/WestVirginia_$dir.zip"
	( cd "build/$dir" && zip -q -9 "../WestVirginia_$dir.zip" ./* )
	echo "build/WestVirginia_$dir.zip  $(du -h "build/WestVirginia_$dir.zip" | cut -f1)"
}

# The import has to exist before an export can read it.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
# Bake the island, so the build reads it instead of generating it at every launch.
"$GODOT" --headless --path . --script res://tests/BAKE_island.gd | grep "^bake:" || echo "no bake: the build will generate the island at start-up" >&2
case "$WHAT" in
	windows) build "Windows" windows WestVirginia.exe windows_release_x86_64.exe ;;
	linux)   build "Linux" linux WestVirginia.x86_64 linux_release.x86_64 ;;
	both)
		build "Windows" windows WestVirginia.exe windows_release_x86_64.exe
		build "Linux" linux WestVirginia.x86_64 linux_release.x86_64 ;;
	*) echo "usage: $0 [windows|linux|both]" >&2; exit 2 ;;
esac
