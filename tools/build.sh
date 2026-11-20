#!/usr/bin/env bash
# Build the executables: one self-contained file each (the project is packed
# into the binary), zipped under build/.
#
#   tools/build.sh            windows and linux
#   tools/build.sh windows    build/GaiaSphereDemo_windows.zip
#   tools/build.sh linux      build/GaiaSphereDemo_linux.zip
#   tools/build.sh android    build/GaiaSphereDemo_android.apk (arm64, debug-signed)
#   tools/build.sh all        all three
#
# Android also needs the Android SDK (ANDROID_HOME, with build-tools and a
# platform) and a JDK (JAVA_HOME, or `java` on the path); it makes itself a debug
# keystore and tells Godot where those are.
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
	rm -f "build/GaiaSphereDemo_$dir.zip"
	( cd "build/$dir" && zip -q -9 "../GaiaSphereDemo_$dir.zip" ./* )
	echo "build/GaiaSphereDemo_$dir.zip  $(du -h "build/GaiaSphereDemo_$dir.zip" | cut -f1)"
}

# The import has to exist before an export can read it.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
# Bake the island, so the build reads it instead of generating it at every launch.
"$GODOT" --headless --path . --script res://tests/BAKE_island.gd | grep "^bake:" || echo "no bake: the build will generate the island at start-up" >&2
android() {
	local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
	[ -d "$sdk" ] || { echo "android: set ANDROID_HOME to the Android SDK" >&2; exit 1; }
	local java_home="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
	local keystore="$HOME/.android/debug.keystore"
	if [ ! -f "$keystore" ]; then
		mkdir -p "$HOME/.android"
		keytool -genkeypair -keyalg RSA -alias androiddebugkey -keypass android -keystore "$keystore" \
			-storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12 >/dev/null 2>&1
	fi
	# Godot reads these from its editor settings, not from the project.
	python3 - "$sdk" "$java_home" "$keystore" "$(echo "$VER" | cut -d. -f1,2)" <<'PY'
import os, re, sys
sdk, java, keystore, ver = sys.argv[1:5]
path = os.path.expanduser("~/.config/godot/editor_settings-%s.tres" % ver)
os.makedirs(os.path.dirname(path), exist_ok=True)
s = open(path).read() if os.path.exists(path) else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
for k, v in {"export/android/android_sdk_path": sdk, "export/android/java_sdk_path": java,
             "export/android/debug_keystore": keystore, "export/android/debug_keystore_user": "androiddebugkey",
             "export/android/debug_keystore_pass": "android"}.items():
    line = '%s = "%s"' % (k, v)
    s, n = re.subn(r"(?m)^%s = .*$" % re.escape(k), lambda m: line, s)
    if not n:
        s = s.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(s)
PY
	[ -f "$TEMPLATES/android_debug.apk" ] || python3 tools/fetch_export_template.py android_debug.apk android_release.apk
	mkdir -p build/android
	"$GODOT" --headless --path . --export-debug "Android" build/android/GaiaSphereDemo.apk
	[ -s build/android/GaiaSphereDemo.apk ] || { echo "no build/android/GaiaSphereDemo.apk: the export failed" >&2; exit 1; }
	cp build/android/GaiaSphereDemo.apk build/GaiaSphereDemo_android.apk
	echo "build/GaiaSphereDemo_android.apk  $(du -h build/GaiaSphereDemo_android.apk | cut -f1)"
}

case "$WHAT" in
	windows) build "Windows" windows GaiaSphereDemo.exe windows_release_x86_64.exe ;;
	linux)   build "Linux" linux GaiaSphereDemo.x86_64 linux_release.x86_64 ;;
	both)
		build "Windows" windows GaiaSphereDemo.exe windows_release_x86_64.exe
		build "Linux" linux GaiaSphereDemo.x86_64 linux_release.x86_64 ;;
	android) android ;;
	all)
		build "Windows" windows GaiaSphereDemo.exe windows_release_x86_64.exe
		build "Linux" linux GaiaSphereDemo.x86_64 linux_release.x86_64
		android ;;
	*) echo "usage: $0 [windows|linux|both|android|all]" >&2; exit 2 ;;
esac
