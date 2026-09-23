#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $# == 0 ]] || fail 'Usage: bash /path/to/bundle/install-desktop.sh'
for tool in mkdir install mktemp rm; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing required tool: $tool"
done

script=${BASH_SOURCE[0]}
[[ $script == */* ]] || script=./$script
# The suffix preserves even trailing newlines during command substitution.
bundle=$(cd -P -- "${script%/*}" && printf '%s/.' "$PWD")
bundle=${bundle%/.}
if [[ -n ${XDG_DATA_HOME:-} ]]; then
  data_home=$XDG_DATA_HOME
elif [[ -n ${HOME:-} ]]; then
  data_home="$HOME/.local/share"
else
  fail 'Neither XDG_DATA_HOME nor HOME is set.'
fi
[[ $data_home == /* ]] || fail 'The user data directory must be an absolute path.'
case "$script$bundle$data_home" in
  *$'\n'*|*$'\r'*) fail 'Paths containing newlines are not supported.' ;;
esac

binary="$bundle/feiniumusic"
template="$bundle/com.feiniu.music.desktop"
icon="$bundle/share/icons/hicolor/256x256/apps/com.feiniu.music.png"
[[ -x $binary ]] || fail "Missing executable: $binary"
[[ -f $template ]] || fail "Missing desktop template: $template"
[[ -f $icon ]] || fail "Missing icon: $icon"

# Quote one Exec argument, then escape backslashes for Desktop Entry parsing.
# Percent signs are field-code escapes, not shell escapes. Never use eval.
exec_path=${binary//\\/\\\\}
exec_path=${exec_path//\"/\\\"}
exec_path=${exec_path//\$/\\\$}
exec_path=${exec_path//\`/\\\`}
exec_path=${exec_path//%/%%}
exec_path=${exec_path//\\/\\\\}
exec_path=${exec_path//$'\t'/\\t}

applications="$data_home/applications"
icons="$data_home/icons/hicolor/256x256/apps"
mkdir -p -- "$applications" "$icons"
temporary=$(mktemp "$applications/.com.feiniu.music.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
while IFS= read -r line || [[ -n $line ]]; do
  case "$line" in
    # GLib 在展开 %% 前检查可执行文件；把路径作为参数传递，保留百分号目录。
    Exec=*) printf 'Exec=/bin/sh -c %s sh "%s"\n' '"exec \\"\\$1\\""' "$exec_path" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$template" > "$temporary"
install -m 644 -- "$icon" "$icons/com.feiniu.music.png"
install -m 644 -- "$temporary" "$applications/com.feiniu.music.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications" \
    || printf 'Warning: could not refresh the user desktop database.\n' >&2
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$data_home/icons/hicolor" \
    || printf 'Warning: could not refresh the user icon cache.\n' >&2
fi
printf 'Installed launcher: %s\nKeep the bundle at: %s\n' \
  "$applications/com.feiniu.music.desktop" "$bundle"
