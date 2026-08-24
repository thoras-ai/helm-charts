#!/usr/bin/env bash
#
# seed-credentials.sh — render the chart's thoras-credentials Secret with
# generated values so it can be captured by external secret management.
#
# Emits a single Kubernetes Secret manifest to stdout. Pipe it into your
# secret tooling (sealed-secrets, ExternalSecrets, `kubectl apply`, or paste
# the values into Vault / AWS Secrets Manager).
#
# Then set `existingSecret.secretName: thoras-credentials` in your values
# file and the chart will use the operator-managed Secret on every install.
#
# Usage:
#   hack/seed-credentials.sh [OPTIONS] > thoras-credentials.yaml
#
# Options:
#   --namespace <ns>       Target namespace (default: thoras).
#   --license-key <key>    Thoras license key. Only used to determine cloud-
#                          sync/Slack activation via other flags; the license
#                          key lives in thoras-secret-registry, not this
#                          Secret. Required.
#   --slack-url <url>      Slack webhook URL. Omit to leave Slack disabled.
#   --cloud-sync-key <k>   Cloud-sync cluster key. Requires --cloud-sync-id.
#   --cloud-sync-id <id>   Cloud-sync cluster key ID. Requires --cloud-sync-key.
#   --external-dsn <dsn>   External Timescale DSN. Omit for in-cluster mode.
#   --chart <path>         Path to a local chart checkout (default: use the
#                          published thoras/thoras repo).
#   -h, --help             Show this help.
#
# Requires: helm, openssl.

set -euo pipefail

NAMESPACE="thoras"
LICENSE_KEY=""
SLACK_URL=""
CLOUD_KEY=""
CLOUD_ID=""
EXTERNAL_DSN=""
CHART_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --namespace)      NAMESPACE="$2"; shift 2 ;;
    --license-key)    LICENSE_KEY="$2"; shift 2 ;;
    --slack-url)      SLACK_URL="$2"; shift 2 ;;
    --cloud-sync-key) CLOUD_KEY="$2"; shift 2 ;;
    --cloud-sync-id)  CLOUD_ID="$2"; shift 2 ;;
    --external-dsn)   EXTERNAL_DSN="$2"; shift 2 ;;
    --chart)          CHART_PATH="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | head -n -1
      exit 0
      ;;
    *)
      echo "error: unknown flag $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$LICENSE_KEY" ]; then
  echo "error: --license-key is required" >&2
  exit 1
fi

# Random values for the passwords/secrets we generate. openssl base64 output
# is fine as plaintext — the chart's b64enc will encode it again into the
# Secret data field.
TIMESCALE_PASSWORD=$(openssl rand -hex 16)
API_CLIENT_SECRET=$(openssl rand -base64 24 | tr -d '=+/' | head -c 32)

SET_ARGS=(
  --set "thorasLicenseKey=${LICENSE_KEY}"
  --set "metricsCollector.timescale.password=${TIMESCALE_PASSWORD}"
  --set "apiClientSecret.secret=${API_CLIENT_SECRET}"
)

if [ -n "$EXTERNAL_DSN" ]; then
  SET_ARGS+=( --set "externalTimescale.dsn=${EXTERNAL_DSN}" )
fi

if [ -n "$SLACK_URL" ]; then
  SET_ARGS+=(
    --set "slackWebhook.url=${SLACK_URL}"
    --set "slackWebhook.existingSecret.secretKey=slack-webhook-url"
  )
fi

if [ -n "$CLOUD_KEY" ] || [ -n "$CLOUD_ID" ]; then
  if [ -z "$CLOUD_KEY" ] || [ -z "$CLOUD_ID" ]; then
    echo "error: --cloud-sync-key and --cloud-sync-id must be used together" >&2
    exit 1
  fi
  SET_ARGS+=(
    --set "cloudSync.clusterKey=${CLOUD_KEY}"
    --set "cloudSync.clusterKeyID=${CLOUD_ID}"
    --set "cloudSync.existingSecret.secretKey=cloud-sync-cluster-key"
  )
fi

CHART_REF="${CHART_PATH:-thoras/thoras}"

helm template thoras "${CHART_REF}" \
  --namespace "${NAMESPACE}" \
  --show-only templates/credentials-secret.yaml \
  "${SET_ARGS[@]}"
