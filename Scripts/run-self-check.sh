#!/bin/sh
# Use the executable from Xcode's built TaskEase.app product.
set -eu
app_executable=${1:?Pass TaskEase.app/Contents/MacOS/TaskEase}
case "$app_executable" in
  */TaskEase.app/Contents/MacOS/TaskEase) ;;
  *) printf '%s\n' 'Expected the built TaskEase application executable.' >&2; exit 2 ;;
esac
"$app_executable" --self-test
