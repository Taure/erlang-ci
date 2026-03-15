#!/usr/bin/env bash
# Unit tests for start-services.sh
# Creates a mock docker binary to capture commands without running containers.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

# Create a temp dir with a mock docker binary
MOCK_DIR=$(mktemp -d)
CALL_LOG="$MOCK_DIR/docker_calls.log"
cat > "$MOCK_DIR/docker" << 'MOCK'
#!/usr/bin/env bash
echo "docker $*" >> "$CALL_LOG"
MOCK
chmod +x "$MOCK_DIR/docker"
trap 'rm -rf "$MOCK_DIR"' EXIT

run_script() {
  > "$CALL_LOG"
  CALL_LOG="$CALL_LOG" PATH="$MOCK_DIR:$PATH" \
    bash "$SCRIPT_DIR/start-services.sh" 2>&1
}

get_calls() {
  cat "$CALL_LOG" 2>/dev/null || echo ""
}

assert_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$CALL_LOG" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$CALL_LOG" 2>/dev/null; then
    echo "  FAIL: $label"
    echo "    expected NOT to find: $needle"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

assert_empty() {
  local label="$1"
  if [ ! -s "$CALL_LOG" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected no docker calls, got:"
    cat "$CALL_LOG" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

echo "== No services enabled =="
ENABLE_POSTGRES=false ENABLE_KAFKA=false \
  run_script > /dev/null
assert_empty "no docker calls"

echo "== Defaults (env not set) =="
run_script > /dev/null
assert_empty "nothing starts by default"

echo "== Postgres only =="
ENABLE_POSTGRES=true POSTGRES_VERSION=17 PGPORT=5432 PGUSER=postgres PGPASSWORD=secret PGDATABASE=test_db \
ENABLE_KAFKA=false \
  run_script > /dev/null
assert_contains "starts postgres container" "docker run -d --name postgres"
assert_contains "uses correct image" "postgres:17"
assert_contains "maps port" "-p 5432:5432"
assert_contains "sets POSTGRES_USER" "POSTGRES_USER=postgres"
assert_contains "sets POSTGRES_PASSWORD" "POSTGRES_PASSWORD=secret"
assert_contains "sets POSTGRES_DB" "POSTGRES_DB=test_db"
assert_contains "waits for ready" "pg_isready"
assert_not_contains "no kafka" "apache/kafka"

echo "== Kafka only =="
ENABLE_POSTGRES=false \
ENABLE_KAFKA=true KAFKA_VERSION=3.9 KAFKA_PORT=9092 \
  run_script > /dev/null
assert_contains "starts kafka container" "docker run -d --name kafka"
assert_contains "uses correct image" "apache/kafka:3.9"
assert_contains "maps port" "-p 9092:9092"
assert_contains "sets KRaft mode" "KAFKA_PROCESS_ROLES=broker,controller"
assert_contains "waits for ready" "kafka-broker-api-versions"
assert_not_contains "no postgres" "docker run -d --name postgres"

echo "== Both services =="
ENABLE_POSTGRES=true POSTGRES_VERSION=16 PGPORT=5555 PGUSER=admin PGPASSWORD=pass PGDATABASE=mydb \
ENABLE_KAFKA=true KAFKA_VERSION=3.8 KAFKA_PORT=19092 \
  run_script > /dev/null
assert_contains "starts postgres" "postgres:16"
assert_contains "postgres custom port" "-p 5555:5432"
assert_contains "starts kafka" "apache/kafka:3.8"
assert_contains "kafka custom port" "-p 19092:9092"
assert_contains "kafka advertised listener uses custom port" "PLAINTEXT://localhost:19092"

echo "== Custom postgres version =="
ENABLE_POSTGRES=true POSTGRES_VERSION=15 PGPORT=5432 PGUSER=u PGPASSWORD=p PGDATABASE=d \
ENABLE_KAFKA=false \
  run_script > /dev/null
assert_contains "postgres 15" "postgres:15"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
