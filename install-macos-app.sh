#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Full Xcode is required. Install and open Xcode once, then run this installer again." >&2
  exit 1
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_dir" || "$developer_dir" == *"/CommandLineTools" ]]; then
  echo "Full Xcode is required. Select it in Xcode > Settings > Locations, then run this installer again." >&2
  exit 1
fi

brew_command="$(command -v brew || true)"
if [[ -z "$brew_command" && -x /opt/homebrew/bin/brew ]]; then
  brew_command=/opt/homebrew/bin/brew
elif [[ -z "$brew_command" && -x /usr/local/bin/brew ]]; then
  brew_command=/usr/local/bin/brew
fi

if [[ -n "$brew_command" ]]; then
  brew_prefix="$("$brew_command" --prefix)"
  export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if [[ -z "$brew_command" ]]; then
    echo "Homebrew is required to install XcodeGen. Install Homebrew, then run this installer again." >&2
    exit 1
  fi
  "$brew_command" install xcodegen
fi

if ! command -v python3 >/dev/null 2>&1; then
  if [[ -z "$brew_command" ]]; then
    echo "Python 3 is required. Install Python 3 or Homebrew, then run this installer again." >&2
    exit 1
  fi
  "$brew_command" install python
fi

cd "$repo_root"
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
./.venv/bin/python -m pip install -r requirements.txt

xcodegen generate --spec macOSWidget/project.yml
xcodebuild -project macOSWidget/SQLPasuyo.xcodeproj \
  -scheme SQLPasuyo -configuration Release \
  -derivedDataPath build build

install_dir="${HOME}/Applications"
app_source="$repo_root/build/Build/Products/Release/SQLPasuyo.app"
app_destination="$install_dir/SQLPasuyo.app"
mkdir -p "$install_dir"
/usr/bin/ditto "$app_source" "$app_destination"
open "$app_destination"

echo "Installed SQL Pasuyo in $app_destination"
