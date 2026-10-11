#!/usr/bin/env bash
# Public repo: refuse statements/exports outside fixtures/.
bad=0
for f in "$@"; do
  case "$f" in
    fixtures/*|docs/*) ;;
    *.pdf|*.ofx|*.qfx|*.sqlite|*.db|*.dump) echo "blocked (looks like real data): $f"; bad=1 ;;
  esac
done
exit $bad
