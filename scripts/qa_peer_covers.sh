#!/usr/bin/env bash
# Peer cover cache isolation -- smoke test
#
# Runs the automatically-verifiable portion of the QA plan:
#   1. flutter analyze on every file touched by the feature
#   2. flutter test on the three feature-specific test files
#   3. i18n keys present in en.po + fr.po
#   4. INVARIANT anchor comment still in place
#   5. Peer callsites still tagged with isPeerCover: true
#
# The UI / dual-device scenarios from the manual QA plan still need to be
# run by hand -- this script only catches regressions that a shell can see.
#
# Usage: bash bibliogenius-app/scripts/qa_peer_covers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$APP_DIR"

# Files created by this feature. We expect a clean analyze here. The
# modified files (settings_screen, theme_provider, etc.) carry a large
# backlog of pre-existing lints unrelated to this work, so we don't gate
# on their analyzer output -- the feature tests below cover them.
NEW_SOURCES=(
  lib/widgets/peer_book_cover_cache_manager.dart
)

FEATURE_TESTS=(
  test/widgets/peer_book_cover_cache_manager_test.dart
  test/widgets/peer_cover_display_gate_test.dart
  test/providers/theme_provider_peer_covers_test.dart
)

REQUIRED_I18N_KEYS=(
  settings_peer_covers_section
  peer_cover_display_enabled
  peer_cover_display_enabled_desc
  peer_cover_cache_cap
  peer_cover_cache_cap_desc
  peer_cover_cache_usage_title
  peer_cover_cache_usage
  peer_cover_cache_refresh
  peer_cover_cache_clear
  peer_cover_cache_clear_title
  peer_cover_cache_clear_body
  peer_cover_cache_clear_action
  peer_cover_cache_clear_done
)

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { printf "${GREEN}✔${RESET} %s\n" "$1"; }
fail() { printf "${RED}✘${RESET} %s\n" "$1"; exit 1; }

step() { printf "\n${BOLD}==> %s${RESET}\n" "$1"; }

step "1/5 flutter analyze (new files only)"
ANALYZE_OUT=$(flutter analyze "${NEW_SOURCES[@]}" "${FEATURE_TESTS[@]}" 2>&1 || true)
if echo "$ANALYZE_OUT" | grep -qE "info •|warning •|error •"; then
  printf "%s\n" "$ANALYZE_OUT"
  fail "analyze found issues in new files (see above)"
fi
pass "no analyzer issues in new files"

step "2/5 flutter test (feature-specific)"
if ! flutter test "${FEATURE_TESTS[@]}" 2>&1 | tail -5; then
  fail "flutter test failed"
fi
pass "all feature tests green"

step "3/5 i18n keys present in en.po and fr.po"
for locale in en fr; do
  for key in "${REQUIRED_I18N_KEYS[@]}"; do
    if ! grep -q "^msgid \"$key\"$" "assets/i18n/$locale.po"; then
      fail "missing key \"$key\" in assets/i18n/$locale.po"
    fi
  done
  pass "$locale.po: all 13 keys present"
done

step "4/5 INVARIANT anchor still in place"
if ! grep -q "INVARIANT -- do not eagerly fetch peer cover bytes" \
     lib/screens/peer_book_list_screen.dart; then
  fail "INVARIANT comment removed from peer_book_list_screen.dart"
fi
pass "invariant comment present"

step "5/5 peer callsites tagged with isPeerCover: true"
PEER_USAGES=$(grep -c "isPeerCover: true" lib/screens/peer_book_list_screen.dart)
# Expected: 3 direct CachedBookCover / BookCoverCard usages in the peer
# screen (coverGrid card, list leading, detail-sheet cover). If the count
# ever dips below 3, a peer view is leaking onto the local cache.
if [ "$PEER_USAGES" -lt 3 ]; then
  fail "expected >=3 isPeerCover: true in peer_book_list_screen.dart, found $PEER_USAGES"
fi
pass "$PEER_USAGES peer callsites tagged"

printf "\n${GREEN}${BOLD}All smoke tests passed.${RESET}\n"
printf "Manual QA (toggle UX, dual-device sync, RGAA/VoiceOver) still required.\n"
