#!/bin/zsh
# Run an OpenStream Apple build/test on Dev-Mini (owner rule 2026-10-05: no builds, tests or sims on the Studio).
# Usage: scripts/mini.sh <command…>        e.g.  scripts/mini.sh swift test
#        scripts/mini.sh --sync-only
# Syncs this tree (no build products, no private fixtures) to dev-mini:~/Developer/openstream-build/src/native/apple,
# then runs the command there from that directory through ~/Developer/bin/buildlock.sh (one heavy job at a time).
# The command runs in zsh with DEVELOPER_DIR set; quote it if it has pipes:  scripts/mini.sh 'swift test 2>&1 | tail -5'
set -euo pipefail
HOST=${OPENSTREAM_MINI:-dev-mini}
DEST='~/Developer/openstream-build/src/native/apple'
HERE=${0:A:h:h}
ssh $HOST "mkdir -p $DEST"
rsync -a --delete \
  --exclude '.build/' --exclude 'Apps/build/' --exclude '*.xcresult' --exclude 'DerivedData*/' \
  --exclude 'Tests/Fixtures/private/' --exclude 'Tests/Fixtures/out/tmp/' --exclude '__pycache__/' \
  --exclude 'verification-artifacts/' --exclude 'design/' --exclude '.git/' \
  "$HERE/" "$HOST:${DEST/#\~/\$HOME}/" 2>/dev/null || rsync -a --delete \
  --exclude '.build/' --exclude 'Apps/build/' --exclude '*.xcresult' --exclude 'DerivedData*/' \
  --exclude 'Tests/Fixtures/private/' --exclude 'Tests/Fixtures/out/tmp/' --exclude '__pycache__/' \
  --exclude 'verification-artifacts/' --exclude 'design/' --exclude '.git/' \
  "$HERE/" "$HOST:Developer/openstream-build/src/native/apple/"
[[ ${1:-} == --sync-only ]] && exit 0
(( $# )) || { print -u2 "usage: scripts/mini.sh <command…>"; exit 2; }
CMD="$*"
ssh $HOST "cd $DEST && ~/Developer/bin/buildlock.sh zsh -c ${(q)CMD}"
