#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Warning: %s\n' "$*" >&2; }

build=true
case "${1:-}" in
  '') [[ $# == 0 ]] || fail 'Empty argument is not supported.' ;;
  --no-build) build=false ;;
  --help|-h)
    printf 'Usage: bash scripts/package_linux.sh [--no-build]\n'
    exit 0 ;;
  *) fail "Unknown argument: $1" ;;
esac
[[ $# -le 1 ]] || fail 'Expected at most one argument.'

for tool in uname env ldd patchelf readlink cp install mkdir mktemp rm mv tar gzip; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing required tool: $tool"
done
if $build; then
  command -v flutter >/dev/null 2>&1 || fail 'Missing required tool: flutter (or use --no-build).'
fi
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail 'Linux x86_64 is required.'

script=${BASH_SOURCE[0]}
[[ $script == */* ]] || script=./$script
root=$(cd -- "${script%/*}/.." && pwd -P)
bundle="$root/build/linux/x64/release/bundle"
output="$root/build/packages"
version=''
while IFS= read -r line; do
  if [[ $line =~ ^version:[[:space:]]*([0-9][0-9A-Za-z.+-]*)[[:space:]]*(#.*)?$ ]]; then
    version=${BASH_REMATCH[1]}
    break
  fi
done < "$root/pubspec.yaml"
[[ -n $version ]] || fail 'Cannot read version from pubspec.yaml.'
epoch=${SOURCE_DATE_EPOCH:-0}
[[ $epoch =~ ^[0-9]+$ ]] || fail 'SOURCE_DATE_EPOCH must be a non-negative integer.'
name="feiniumusic-${version}-preview-linux-x64"

if $build; then
  (cd -- "$root" && flutter build linux --release)
fi
[[ -x "$bundle/feiniumusic" ]] || fail "Missing executable: $bundle/feiniumusic"
[[ -f "$bundle/lib/libtray_manager_plugin.so" ]] || fail 'Missing libtray_manager_plugin.so in bundle/lib.'

mkdir -p -- "$output"
work=$(mktemp -d "$output/.package-linux.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
stage="$work/$name"
mkdir -- "$stage"
# Dereference links so patching the staged copy cannot change the input bundle.
cp -aL -- "$bundle/." "$stage/"

# An existing bundle may already contain these libraries and an ORIGIN RUNPATH.
# Probe an isolated plugin without its search path to resolve system copies only.
probe="$work/libtray_manager_plugin.so"
cp -L -- "$bundle/lib/libtray_manager_plugin.so" "$probe"
patchelf --remove-rpath "$probe"
ldd_output=$(env -u LD_LIBRARY_PATH -u LD_PRELOAD -u LD_AUDIT LC_ALL=C ldd "$probe") \
  || fail 'ldd failed for the isolated tray plugin.'

libraries=(
  libayatana-appindicator3.so.1
  libayatana-indicator3.so.7
  libayatana-ido3-0.4.so.0
  libdbusmenu-gtk3.so.4
  libdbusmenu-glib.so.4
)
packages=(
  libayatana-appindicator3-1
  libayatana-indicator3-7
  libayatana-ido3-0.4-0
  libdbusmenu-gtk3-4
  libdbusmenu-glib4
)

# Debian/Ubuntu packages must supply their copyright and common license files.
# Other distributions may place these elsewhere; never omit them silently.
missing_license() {
  if [[ -f /etc/debian_version ]]; then
    fail "$* (reinstall the corresponding distribution package)."
  fi
  warn "$*; include the distribution's license files before redistributing."
}

for i in "${!libraries[@]}"; do
  library=${libraries[$i]}
  source=''
  while read -r soname arrow path rest; do
    if [[ $soname == "$library" && $arrow == '=>' && $path == /* ]]; then
      source=$path
      break
    fi
  done <<< "$ldd_output"
  [[ -n $source ]] || fail "Cannot resolve $library from system ldd output; install ${packages[$i]}."
  source=$(readlink -f -- "$source")
  case "$source" in
    /usr/lib/*|/usr/lib64/*|/lib/*|/lib64/*) ;;
    *) fail "Refusing non-system library path: $source" ;;
  esac
  [[ -f $source ]] || fail "Missing system library: $source"
  printf 'Bundling %s from %s\n' "$library" "$source"
  install -m 644 -- "$source" "$stage/lib/$library"
  patchelf --set-rpath '$ORIGIN' "$stage/lib/$library"

  package=${packages[$i]}
  # Use the owning package when available (including renamed/t64 packages).
  if command -v dpkg-query >/dev/null 2>&1; then
    if owner=$(dpkg-query -S "$source" 2>/dev/null); then
      owner=${owner%%: /*}
      owner=${owner%%:*}
      [[ $owner != *$'\n'* && $owner != */* ]] || fail "Ambiguous package owner for $source"
      package=$owner
    fi
  fi
  copyright="/usr/share/doc/$package/copyright"
  if [[ -f $copyright ]]; then
    install -D -m 644 -- "$copyright" "$stage/share/doc/$package/copyright"
  else
    missing_license "Missing copyright for $library: $copyright"
  fi
done
patchelf --set-rpath '$ORIGIN' "$stage/lib/libtray_manager_plugin.so"

# Include the full LGPL/GPL texts used by the five packages' copyright notices.
for license in LGPL-2 LGPL-2.1 LGPL-3 GPL-2 GPL-3; do
  source="/usr/share/common-licenses/$license"
  if [[ -f $source ]]; then
    install -D -m 644 -- "$source" "$stage/share/common-licenses/$license"
  else
    missing_license "Missing common license: $source"
  fi
done

# Also populate desktop assets for --no-build bundles made before these rules.
install -D -m 644 -- "$root/assets/icon/app_icon.png" \
  "$stage/share/icons/hicolor/256x256/apps/com.feiniu.music.png"
install -m 644 -- "$root/linux/com.feiniu.music.desktop" "$root/linux/install-desktop.sh" "$stage/"

# Stable archive ordering, ownership, permissions, timestamps and gzip header.
# The archive is outside the input bundle; publish it only after success.
tar --sort=name --format=gnu --mtime="@$epoch" --owner=0 --group=0 \
  --numeric-owner --mode='u+rwX,go+rX,go-w' -C "$work" -cf - "$name" \
  | gzip -n > "$work/$name.tar.gz"
mv -f -- "$work/$name.tar.gz" "$output/$name.tar.gz"
printf 'Package: %s\n' "$output/$name.tar.gz"
