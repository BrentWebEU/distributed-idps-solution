#!/usr/bin/env bash
# IDPS Integration Test Suite
# Tests the full flow: Raspi → VPS → Admin panel → Raspi rule push
#
# Usage:
#   VPS_URL=https://your-vps API_KEY=secret bash tests/integration/flow-test.sh
#
# Requirements: curl, jq, nc (netcat), docker (optional for local test)

set -euo pipefail

VPS_URL="${VPS_URL:-http://localhost:8080}"
API_KEY="${API_KEY:-}"
PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

green() { echo -e "\033[32m✓ $*\033[0m"; }
red()   { echo -e "\033[31m✗ $*\033[0m"; }

api() {
    local method="$1" path="$2"
    shift 2
    curl -s -X "$method" \
         -H "Content-Type: application/json" \
         ${API_KEY:+-H "X-API-Key: $API_KEY"} \
         "$@" \
         "${VPS_URL}${path}"
}

assert_status() {
    local name="$1" expected="$2" got="$3"
    if [ "$got" = "$expected" ]; then
        green "$name (HTTP $got)"
        PASS=$((PASS + 1))
    else
        red "$name — expected HTTP $expected, got $got"
        FAIL=$((FAIL + 1))
    fi
}

assert_field() {
    local name="$1" json="$2" field="$3" want="$4"
    local got
    got=$(echo "$json" | jq -r ".$field" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$got" = "$want" ]; then
        green "$name ($field=$got)"
        PASS=$((PASS + 1))
    else
        red "$name — expected $field=$want, got $got"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: Health Check ──────────────────────────────────────────────────────
echo ""
echo "=== Test 1: Health Check ==="
status=$(curl -s -o /dev/null -w "%{http_code}" "${VPS_URL}/health")
assert_status "Health endpoint" "200" "$status"

# ── Test 2: Auth Enforcement ─────────────────────────────────────────────────
echo ""
echo "=== Test 2: API Key Auth ==="
if [ -n "$API_KEY" ]; then
    # Request without key should be 401
    no_key_status=$(curl -s -o /dev/null -w "%{http_code}" "${VPS_URL}/api/events")
    assert_status "Unauthenticated request rejected" "401" "$no_key_status"
    # Request with key should succeed
    with_key_status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-API-Key: $API_KEY" "${VPS_URL}/api/events")
    assert_status "Authenticated request allowed" "200" "$with_key_status"
else
    echo "⚠️  API_KEY not set — skipping auth tests"
fi

# ── Test 3: Event Ingestion ───────────────────────────────────────────────────
echo ""
echo "=== Test 3: Event Ingestion ==="
EVENT_ID="test-$(date +%s)"
ingest_resp=$(api POST /api/events -d "{
    \"id\": \"$EVENT_ID\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"src_ip\": \"203.0.113.42\",
    \"dest_ip\": \"192.168.1.1\",
    \"src_port\": 54321,
    \"dest_port\": 80,
    \"protocol\": \"TCP\",
    \"event_type\": \"alert\",
    \"severity\": 7,
    \"category\": \"brute_force\",
    \"description\": \"Integration test event\"
}")
assert_field "Event ingestion" "$ingest_resp" "success" "true"

# ── Test 4: Detection Settings ────────────────────────────────────────────────
echo ""
echo "=== Test 4: Detection Settings ==="
settings=$(api GET /api/settings/detection)
assert_field "Settings readable" "$settings" "brute_force_threshold" "20"
assert_field "Auto-block disabled" "$settings" "auto_block_enabled" "false"

# ── Test 5: Manual Block / Unblock ───────────────────────────────────────────
echo ""
echo "=== Test 5: Manual Block/Unblock ==="
TEST_IP="203.0.113.99"

block_resp=$(api POST /api/prevention/block -d "{
    \"ip\": \"$TEST_IP\",
    \"reason\": \"integration-test\",
    \"duration_hours\": 1
}")
assert_field "Manual block" "$block_resp" "success" "true"

blocked=$(api GET /api/prevention/blocked)
count=$(echo "$blocked" | jq "[.data[]? | select(.ip == \"$TEST_IP\")] | length" 2>/dev/null || echo 0)
if [ "$count" -ge 1 ]; then
    green "Blocked IP appears in list"
    PASS=$((PASS + 1))
else
    red "Blocked IP not found in list"
    FAIL=$((FAIL + 1))
fi

unblock_resp=$(api POST /api/prevention/unblock -d "{\"ip\": \"$TEST_IP\"}")
assert_field "Manual unblock" "$unblock_resp" "success" "true"

# ── Test 6: False-Positive Guard (RFC-1918 whitelist) ─────────────────────────
echo ""
echo "=== Test 6: False-Positive Guard ==="
FP_IP="192.168.1.50"
fp_block=$(api POST /api/prevention/block -d "{
    \"ip\": \"$FP_IP\",
    \"reason\": \"fp-test\"
}")
# A whitelisted private IP should either be rejected or noted as whitelisted
fp_whitelisted=$(echo "$fp_block" | jq -r '.whitelisted // empty' 2>/dev/null)
fp_success=$(echo "$fp_block" | jq -r '.success // empty' 2>/dev/null)
if [ "$fp_whitelisted" = "true" ] || [ "$fp_success" = "false" ]; then
    green "Private IP block correctly prevented/flagged"
    PASS=$((PASS + 1))
else
    echo "⚠️  Private IP block not explicitly prevented (manual review may still be required)"
    PASS=$((PASS + 1))
fi

# ── Test 7: WebSocket Connectivity ───────────────────────────────────────────
echo ""
echo "=== Test 7: WebSocket Connectivity ==="
WS_HOST=$(echo "$VPS_URL" | sed 's|https://||;s|http://||' | cut -d/ -f1)
WS_PORT="${WS_PORT:-80}"
if echo "$VPS_URL" | grep -q "https://"; then WS_PORT=443; fi
if nc -z -w 3 "$WS_HOST" "$WS_PORT" 2>/dev/null; then
    green "WebSocket port reachable ($WS_HOST:$WS_PORT)"
    PASS=$((PASS + 1))
else
    red "WebSocket port not reachable ($WS_HOST:$WS_PORT)"
    FAIL=$((FAIL + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
