#!/bin/sh
set -eu

log() { printf '[helm-sops-cmp] %s\n' "$*" >&2; }

# Validate age key is available
if [ -z "${SOPS_AGE_KEY_FILE:-}" ] || [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
  log "ERROR: SOPS_AGE_KEY_FILE not set or file missing: ${SOPS_AGE_KEY_FILE:-<unset>}"
  exit 1
fi

value_args=""
tmp_files=""

decrypt_and_add() {
  local src="$1"
  local dec="/tmp/dec_$(printf '%s' "$src" | tr '/.' '__').yaml"
  log "Decrypting $src"
  sops --decrypt "$src" > "$dec" \
    || { log "ERROR: sops failed for $src — check age key and encryption"; exit 1; }
  value_args="$value_args -f $dec"
  tmp_files="$tmp_files $dec"
}

add_plain() {
  log "Values    $1"
  value_args="$value_args -f $1"
}

if [ -n "${ARGOCD_ENV_HELM_VALUE_FILES:-}" ]; then
  # Explicit mode: caller controls exactly which files and which are encrypted
  # Format: "values.yaml|../global.yaml|secrets://secrets/secret.yaml"
  for f in $(printf '%s' "$ARGOCD_ENV_HELM_VALUE_FILES" | tr '|' ' '); do
    if printf '%s' "$f" | grep -q '^secrets://'; then
      decrypt_and_add "${f#secrets://}"
    else
      add_plain "$f"
    fi
  done
else
  # Auto-discovery mode: follow project layout conventions
  #   ../global-values.yaml   → plain (repo-wide values)
  #   ../global-secrets.yaml  → decrypt (repo-wide encrypted values)
  #   values.yaml             → plain (app values)
  #   secrets/*.yaml          → decrypt (app encrypted values)
  #   secrets.yaml            → decrypt (app encrypted values, single-file layout)
  [ -f "../global-values.yaml"  ] && add_plain "../global-values.yaml"
  [ -f "../global-secrets.yaml" ] && decrypt_and_add "../global-secrets.yaml"
  [ -f "values.yaml"            ] && add_plain "values.yaml"
  if [ -d "secrets" ]; then
    for f in secrets/*.yaml secrets/*.yml; do
      [ -f "$f" ] && decrypt_and_add "$f"
    done
  fi
  [ -f "secrets.yaml" ] && decrypt_and_add "secrets.yaml"
fi

log "Rendering $ARGOCD_APP_NAME (namespace: $ARGOCD_APP_NAMESPACE)"
helm template "$ARGOCD_APP_NAME" . \
  $value_args \
  --include-crds \
  -n "$ARGOCD_APP_NAMESPACE"

ret=$?
# shellcheck disable=SC2086
rm -f $tmp_files
exit $ret
