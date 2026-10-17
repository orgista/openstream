#!/bin/zsh
# Run an OpenStream Apple build/test on Dev-Mini (owner rule 2026-10-05: no builds, tests or sims on the Studio).
# Usage: scripts/mini.sh <command…>        e.g.  scripts/mini.sh swift test
#        scripts/mini.sh --sync-only
# Syncs this tree (no build products, no private fixtures) to dev-mini:~/Developer/openstream-build/src/native/apple,
# then runs the command there from that directory through ~/Developer/bin/buildlock.sh (one heavy job at a time).
# The command runs in zsh with DEVELOPER_DIR set; quote it if it has pipes:  scripts/mini.sh 'swift test 2>&1 | tail -5'
set -euo pipefail
HOST=${OPENSTREAM_MINI:-dev-mini}
# OPENSTREAM_MINI_DEST: a separate folder for a second tree (a branch worktree), so two trees never sync over
# each other's running build.
DEST=${OPENSTREAM_MINI_DEST:-'~/Developer/openstream-build/src/native/apple'}
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
  "$HERE/" "$HOST:${DEST#\~/}/"
[[ ${1:-} == --sync-only ]] && exit 0
(( $# )) || { print -u2 "usage: scripts/mini.sh <command…>"; exit 2; }
CMD="$*"
# OPENSTREAM_MINI_LANE=compile: swift test / builds with no simulator or device take the second lock and can run beside
# one simulator/device job (owner 2026-10-16). Anything that boots a simulator or touches a device uses the default lane.
LOCK=buildlock.sh; [[ ${OPENSTREAM_MINI_LANE:-} == compile ]] && LOCK=buildlock-compile.sh
ssh $HOST "cd $DEST && ~/Developer/bin/$LOCK zsh -c ${(q)CMD}"
