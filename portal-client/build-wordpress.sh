#!/usr/bin/env bash
# Builds barncrm-portal.zip, the WordPress plugin with the portal client inside it, for
# Plugins, Add New, Upload Plugin. Usage: bash portal-client/build-wordpress.sh [output.zip]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$PWD/barncrm-portal.zip}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "$here/wordpress/barncrm-portal" "$work/barncrm-portal"
cp "$here/src/portalApi.js" "$here/src/portalApp.js" "$here/src/messages.js" "$work/barncrm-portal/js/"
rm -f "$out"
(cd "$work" && zip -qr "$out" barncrm-portal)
echo "Built $out"
