---
# helm-zg742gjj
title: "Release a chart only when a merged commit changes its version line"
status: accepted
type: decision
tags:
    - backfill
    - chart
    - release
    - ci
    - versioning
created_at: 2026-11-07T02:18:26Z
updated_at: 2026-11-07T02:18:26Z
decided_at: 2026-10-22
refs:
    - "pr:thoras-ai/helm-charts#766"
    - "pr:thoras-ai/helm-charts#758"
    - "pr:thoras-ai/helm-charts#816"
    - "pr:thoras-ai/helm-charts#905"
    - "pr:thoras-ai/helm-charts#910"
    - "pr:thoras-ai/helm-charts#924"
    - "pr:thoras-ai/helm-charts#955"
    - "pr:thoras-ai/helm-charts#972"
    - "doc:AGENTS.md"
    - "code:.github/workflows/release.yml"
---

## Context
`release.yml` runs on every push to `main`. Adding a second chart exposed that chart-releaser discovers `charts/*`, so any bump would have published an empty `thoras-console` (#905). Later, chart publication could outrun the platform images it references, which #955 addresses.

## Decision
- A chart releases when the diff of the merge commit against its first parent changes that chart's `version:` line. Other edits to `Chart.yaml` release nothing. Bumps live in dedicated release PRs.
- Charts are listed explicitly in the workflow and packaged with `skip_packaging`, so only moved charts publish (#924).
- If `thorasVersion` moved in that commit, the release stops unless platform's "Release on tag" run succeeded. An unreachable GitHub API also blocks (#955).
- Release notes dispatch only on a `thoras` bump; the platform generator reads `thoras-<version>` tags and `thorasVersion` (#924).
- App versions are platform tags and chart versions are separate numbers. A console sample that used a `thoras` chart version as `consoleVersion` failed with `ImagePullBackOff` (#924).
- A bad release is pulled by removing its entry from `index.yaml` on `gh-pages` (#758, #816).

## Options considered
- Dropping `skip_packaging` to clear the chart-releaser failure: rejected, because auto-discovery returns (#910).
- Pinning a tagged chart-releaser version: not possible, because v1.6.0 and v1.7.0 both carry the `latest_tag` bug. The action is pinned to SHA `3e001cb8` (#910).
- Replacing the action with direct `cr upload` and `cr index` calls: suggested as a follow-up in #910, not done.

## Consequences
- Detection compares only the tip commit with its parent, so a bump reaches `main` only through a PR (AGENTS.md).
- The image check covers `thorasVersion` only. A console-only release is not checked (#955).
- A new chart needs a detection check and a `helm package` line.
- `skip_existing` makes re-runs safe, and also means re-running a failed job doesn't prove a fix (#910).

## Provenance
Stated: the PRs cited above, AGENTS.md, and the workflow, which matches them today.
Inferred: nothing material.
