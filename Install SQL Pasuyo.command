#!/bin/bash

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root" || exit 1

./install-macos-app.sh
install_status=$?

if [[ $install_status -eq 0 ]]; then
  echo
  echo "SQL Pasuyo is installed and open. Enter your GitHub and Teamwork credentials in the app."
else
  echo
  echo "Installation did not finish. Read the message above, fix the requirement, and double-click this file again."
fi

echo
read -r -p "Press Return to close this window. " _
exit "$install_status"
