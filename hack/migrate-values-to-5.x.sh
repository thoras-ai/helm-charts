#!/usr/bin/env bash
#
# migrate-values-to-5.x.sh — rewrite a pre-5.0 Thoras values file into the 5.0 shape.
#
# Chart 5.0 collapsed the six credential Secrets (thoras-timescale-password,
# api-client-secret, thoras-cloud-sync, thoras-slack, plus the derived DSN)
# into one unified `thoras-credentials` Secret, and renamed the values-side
# fields to a consistent `existingSecret: {secretName, ...Key}` shape.
#
# This script rewrites the flat 4.x field names to their 5.0 replacements.
# It is idempotent: run it twice and the second run is a no-op.
#
# Usage:
#   hack/migrate-values-to-5.x.sh <values-file> [<values-file>...]
#
# Requires: yq v4+ (the mikefarah go implementation).
#
# The script does not touch chart-managed credentials in the cluster. See
# charts/thoras/README.md#upgrading-to-chart-5x for the full upgrade procedure.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <values-file> [<values-file>...]" >&2
  exit 1
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "error: $f does not exist" >&2
    exit 1
  fi

  # Each rename is guarded on `has(...)` so re-runs are no-ops. yq's `|=`
  # in-place update expression walks the tree once per top-level rename.
  yq -i '
    (select(.imageCredentials | has("password"))
      | .thorasLicenseKey = .imageCredentials.password
      | del(.imageCredentials.password)) // . |
    (select(.imageCredentials | has("secretRef"))
      | .imageCredentials.existingSecret.secretName = .imageCredentials.secretRef
      | del(.imageCredentials.secretRef)) // . |
    (select(.externalTimescale | has("secretRefName"))
      | .externalTimescale.existingSecret.secretName = .externalTimescale.secretRefName
      | del(.externalTimescale.secretRefName)) // . |
    (select(.externalTimescale | has("secretRefKey"))
      | .externalTimescale.existingSecret.dsnKey = .externalTimescale.secretRefKey
      | del(.externalTimescale.secretRefKey)) // . |
    (select(has("slackWebhookUrl"))
      | .slackWebhook.url = .slackWebhookUrl
      | del(.slackWebhookUrl)) // . |
    (select(has("slackWebhookUrlSecretRefName"))
      | .slackWebhook.existingSecret.secretName = .slackWebhookUrlSecretRefName
      | del(.slackWebhookUrlSecretRefName)) // . |
    (select(has("slackWebhookUrlSecretRefKey"))
      | .slackWebhook.existingSecret.secretKey = .slackWebhookUrlSecretRefKey
      | del(.slackWebhookUrlSecretRefKey)) // . |
    (select(.cloudSync | has("clusterKeySecretRefName"))
      | .cloudSync.existingSecret.secretName = .cloudSync.clusterKeySecretRefName
      | del(.cloudSync.clusterKeySecretRefName)) // . |
    (select(.cloudSync | has("clusterKeySecretRefKey"))
      | .cloudSync.existingSecret.secretKey = .cloudSync.clusterKeySecretRefKey
      | del(.cloudSync.clusterKeySecretRefKey)) // .
  ' "$f"

  echo "migrated: $f"
done
