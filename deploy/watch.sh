#!/bin/bash
# Wrapper launchd invokes. Keeps the plist simple and gives one place to set
# environment (e.g. a Slack webhook) without editing the plist.
#
# Exits 0 even when a release is not yet published: "nothing new" is a normal
# outcome, not a failure, and a non-zero exit would make launchd noisy.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# Passed explicitly so path resolution never depends on how the launcher
# quoted argv - the project path may contain spaces.
export SA_BRIEF_ROOT="$PROJECT_ROOT"

mkdir -p output/logs

# Slack webhook, if you use one. Prefer exporting it here over the plist so
# the secret stays out of a file you might commit:
#   export SA_BRIEF_SLACK_WEBHOOK="https://hooks.slack.com/services/..."

exec ./sa-brief watch >> output/logs/watch.stdout.log 2>&1
