#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Rendering chart with full-extensible-values.yaml"
helm template smoke "$HERE" -f "$HERE/examples/full-extensible-values.yaml" > "$WORK/manifests.yaml"

echo "==> Extracting config.json"
yq '. | select(.kind == "ConfigMap" and (.metadata.name | test("-config$"))) | .data."config.json"' \
  "$WORK/manifests.yaml" > "$WORK/config.json"

# Sanity: rendered JSON has sources
jq -e '.sources | length > 0' < "$WORK/config.json" > /dev/null
echo "    config.json has $(jq '.sources | length' < "$WORK/config.json") sources"

# Pick one source's title to grep for in the served HTML
EXPECTED_TITLE=$(jq -r '.sources[0].title' < "$WORK/config.json")
echo "    expecting served HTML to mention: '$EXPECTED_TITLE'"

echo "==> Starting scalarapi/api-reference container with rendered config as env var"
CID=$(docker run -d --rm \
  -e API_REFERENCE_CONFIG="$(cat "$WORK/config.json")" \
  -p 18080:8080 \
  scalarapi/api-reference:latest)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

# Wait for /health to come up
for i in $(seq 1 15); do
  if curl -sf http://localhost:18080/health > /dev/null; then break; fi
  sleep 1
done

CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/health)
[ "$CODE" = "200" ] || { echo "FAIL /health → $CODE"; exit 1; }

# Caddy substitutes {{env "API_REFERENCE_CONFIG"}} literally into the HTML.
# Confirm our content is present.
BODY=$(curl -sf http://localhost:18080/)
if ! echo "$BODY" | grep -q "$EXPECTED_TITLE"; then
  echo "FAIL: rendered HTML does not contain expected title '$EXPECTED_TITLE'"
  echo "$BODY" | head -40
  exit 1
fi

echo "==> OK — Scalar serves rendered config at /, /health responds 200"
