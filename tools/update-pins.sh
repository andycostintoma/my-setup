#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

nix_cmd=(nix --extra-experimental-features "nix-command flakes")

pypi_version() {
  curl -fsSL "https://pypi.org/pypi/$1/json" | jq -r .info.version
}

npm_version() {
  npm view "$1" version
}

prefetch_file() {
  "${nix_cmd[@]}" store prefetch-file --json --name "$1" "$2"
}

edge_url="https://go.microsoft.com/fwlink/?linkid=2093504"
kumospace_url="https://downloads.kumospace.com/production/macos/universal/latest/Kumospace.dmg"

openviking_version="$(pypi_version openviking)"
graphifyy_version="$(pypi_version graphifyy)"
kimaki_version="$(npm_version kimaki)"
openchamber_version="$(npm_version @openchamber/web)"

edge_prefetch="$(prefetch_file MicrosoftEdge.pkg "$edge_url")"
edge_hash="$(jq -r .hash <<<"$edge_prefetch")"
edge_store_path="$(jq -r .storePath <<<"$edge_prefetch")"
edge_version="$(
  xar -tf "$edge_store_path" \
    | perl -ne 'if (/MicrosoftEdge-([0-9][0-9.]+)\.pkg\/?$/) { print $1; exit }'
)"

kumospace_prefetch="$(prefetch_file Kumospace.dmg "$kumospace_url")"
kumospace_hash="$(jq -r .hash <<<"$kumospace_prefetch")"
kumospace_store_path="$(jq -r .storePath <<<"$kumospace_prefetch")"
set +o pipefail
kumospace_version="$(
  7z e -so "$kumospace_store_path" 'Kumospace/Kumospace.app/Contents/Info.plist' 2>/dev/null \
    | /usr/bin/plutil -extract CFBundleShortVersionString raw -o - -
)"
set -o pipefail

if [ -z "$edge_version" ] || [ -z "$kumospace_version" ]; then
  printf '%s\n' 'Failed to extract app versions from downloaded artifacts.' >&2
  exit 1
fi

cat > modules/pins.nix <<EOF
{
  openviking.version = "$openviking_version";
  graphifyy.version = "$graphifyy_version";

  kimaki.version = "$kimaki_version";
  openchamber.version = "$openchamber_version";

  microsoftEdge = {
    version = "$edge_version";
    url = "$edge_url";
    hash = "$edge_hash";
  };

  kumospace = {
    version = "$kumospace_version";
    url = "$kumospace_url";
    hash = "$kumospace_hash";
  };
}
EOF

printf 'Updated pins: openviking %s, graphifyy %s, kimaki %s, openchamber %s, microsoft-edge %s, kumospace %s\n' \
  "$openviking_version" \
  "$graphifyy_version" \
  "$kimaki_version" \
  "$openchamber_version" \
  "$edge_version" \
  "$kumospace_version"
