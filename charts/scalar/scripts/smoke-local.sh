#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Rendering chart with full-extensible-values.yaml"
helm template smoke "$HERE" -f "$HERE/examples/full-extensible-values.yaml" > "$WORK/manifests.yaml"

echo "==> Extracting config.json"
yq '. | select(.kind == "ConfigMap" and (.metadata.name | test("-config$"))) | .data."config.json"' \
  "$WORK/manifests.yaml" | jq -e '.sources | length > 0' > /dev/null
echo "    config.json valid"

echo "==> Running scalarapi/api-reference container with rendered config"
yq '. | select(.kind == "ConfigMap" and (.metadata.name | test("-config$"))) | .data."config.json"' \
  "$WORK/manifests.yaml" > "$WORK/config.json"

CID=$(docker run -d --rm \
  -v "$WORK/config.json:/configs/config.json:ro" \
  -e API_REFERENCE_CONFIG_FILE=/configs/config.json \
  -p 18080:8080 \
  scalarapi/api-reference:latest)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

# Wait for nginx to come up
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf http://localhost:18080/configs/config.json > /dev/null; then
    break
  fi
  sleep 1
done

CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/)
[ "$CODE" = "200" ] || { echo "Scalar / returned $CODE"; exit 1; }
echo "==> OK — Scalar serves rendered config locally"
