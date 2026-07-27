#!/usr/bin/env bash

set -euo pipefail

chart_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

rendered=$(helm template auth-smoke "$chart_dir" \
  --namespace core \
  --set oauth2.enabled=true \
  --set-string oauth2.audienceBaseURL=https://api.stawi.org \
  --set-string oauth2.resourcePath=/authentication \
  --set-string 'oauth2.requestedAudiencePaths[0]=/profile' \
  --set-string 'oauth2.requestedAudiencePaths[1]=/tenancy' \
  --set-string oauth2.clientAssertionAudience=https://oauth2.stawi.org/oauth2/token \
  --set migration.enabled=true)

grep -Fq 'value: "https://api.stawi.org/profile,https://api.stawi.org/tenancy"' <<<"$rendered"
grep -Fq 'value: "https://api.stawi.org/authentication"' <<<"$rendered"
grep -Fq 'value: "https://api.stawi.org"' <<<"$rendered"
grep -Fq 'value: "https://oauth2.stawi.org/oauth2/token"' <<<"$rendered"
grep -Fq 'name: auth-smoke-oauth2-cli' <<<"$rendered"
grep -Fq 'value: "enforced"' <<<"$rendered"
test "$(grep -Fc 'name: OAUTH2_RESOURCE_AUDIENCE' <<<"$rendered")" -eq 2
test "$(grep -Fc 'name: AUTHORIZATION_MODE' <<<"$rendered")" -eq 2

if grep -Eq 'OAUTH2_(SERVICE_AUDIENCE|JWT_VERIFY_AUDIENCE)' <<<"$rendered"; then
  echo "legacy OAuth audience environment variable rendered" >&2
  exit 1
fi

private_jwt=$(helm template auth-smoke "$chart_dir" \
  --namespace core \
  --set oauth2.enabled=true \
  --set-string oauth2.audienceBaseURL=https://api.stawi.org \
  --set-string oauth2.resourcePath=/authentication \
  --set-string oauth2.clientAssertionAudience=https://oauth2.stawi.org/oauth2/token \
  --set-string oauth2.tokenEndpointAuthMethod=private_key_jwt \
  --set oauth2.privateJWT.enabled=true \
  --set-string oauth2.privateJWT.source=url \
  --set-string oauth2.privateJWT.signerUrl=http://signer.core:8080/sign)

grep -Fq 'name: OAUTH2_PRIVATE_JWT_KEY' <<<"$private_jwt"
if grep -Fq 'name: OAUTH2_SERVICE_CLIENT_SECRET' <<<"$private_jwt"; then
  echo "client secret rendered for private_key_jwt" >&2
  exit 1
fi
if grep -Fq '\"audience\"' <<<"$private_jwt"; then
  echo "client assertion audience leaked into private JWT signer configuration" >&2
  exit 1
fi

if helm template invalid "$chart_dir" --set-string oauth2.audience=service_profile >/dev/null 2>&1; then
  echo "legacy oauth2.audience value was accepted" >&2
  exit 1
fi

if helm template invalid "$chart_dir" \
  --set oauth2.enabled=true \
  --set-string oauth2.audienceBaseURL=https://user@api.stawi.org:443 \
  --set-string oauth2.resourcePath=/profile \
  --set-string oauth2.clientAssertionAudience=https://oauth2.stawi.org/oauth2/token >/dev/null 2>&1; then
  echo "non-canonical audience base URL was accepted" >&2
  exit 1
fi

if helm template invalid "$chart_dir" \
  --set oauth2.enabled=true \
  --set-string oauth2.audienceBaseURL=https://api.stawi.org \
  --set-string oauth2.resourcePath=/profile \
  --set-string oauth2.clientAssertionAudience=https://oauth2.stawi.org/oauth2/token \
  --set-string oauth2.tokenEndpointAuthMethod=private_key_jwt >/dev/null 2>&1; then
  echo "private_key_jwt without privateJWT.enabled was accepted" >&2
  exit 1
fi

echo "colony authentication contract smoke test passed"
