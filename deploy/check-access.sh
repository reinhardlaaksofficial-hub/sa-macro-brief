#!/bin/bash
# Can THIS machine fetch Stats SA directly?
#
#   bash deploy/check-access.sh
#
# Stats SA sits behind Imperva, which serves data files normally to ordinary
# connections but challenges many datacentre IP ranges — GitHub's shared
# Actions runners are challenged, for example. Whether any given host works
# is empirical, so run this on a candidate box BEFORE building anything on
# it: a free-tier VM, an office machine, a prospective self-hosted runner.
#
# Exit 0 = this host fetches releases directly; suitable for release-day capture.
# Exit 1 = challenged; this host can only rebuild already-archived releases.
set -uo pipefail

UA="sa-macro-brief/0.1 (access check; +https://github.com/reinhardlaaksofficial-hub/sa-macro-brief)"

# Stats SA keeps only the CURRENT vintage of the timeseries files — last
# month's zip is deleted outright — so a hardcoded filename goes stale within
# weeks. Walk back from this month until one exists, as the pipeline does.
echo "Checking direct access to statssa.gov.za from $(hostname)..."
found=""
for back in 0 1 2 3; do
  ym=$(date -u -v-"${back}"m +%Y%m 2>/dev/null || date -u -d "-${back} month" +%Y%m)
  url="https://www.statssa.gov.za/timeseriesdata/Excel/P0142.1%20PPI%20New%20series%20from%202013(${ym}).zip"
  tmp="$(mktemp)"
  code=$(curl -s --max-time 60 -A "$UA" -o "$tmp" -w '%{http_code}' "$url")
  type=$(file -b "$tmp" 2>/dev/null || echo unknown)
  size=$(wc -c < "$tmp" | tr -d ' ')
  rm -f "$tmp"
  echo "  ${ym}: HTTP ${code}, ${size} bytes, ${type}"
  case "$code:$type" in
    200:*[Zz]ip*) found="$ym"; break ;;
  esac
  sleep 1
done

echo
if [ -n "$found" ]; then
  echo "PASS — this host fetches Stats SA directly (current vintage: ${found})."
  echo "Suitable for release-day capture: run the watcher here, or register"
  echo "this machine as a self-hosted GitHub Actions runner."
  exit 0
fi

echo "BLOCKED — this host gets a challenge page or an error instead of the file."
echo "It can still rebuild already-archived releases through the Internet"
echo "Archive fallback, but it cannot capture a release on the day, because a"
echo "file published minutes ago is in no archive."
exit 1
