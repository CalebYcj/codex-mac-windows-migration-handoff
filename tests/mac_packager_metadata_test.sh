#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/codex-rehome/scripts/create_mac_codex_migration_package.sh"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

assert_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing file: $1" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq "$pattern" "$file"; then
    echo "unexpected pattern '$pattern' in $file" >&2
    exit 1
  fi
}

assert_json_value() {
  local file="$1"
  local expr="$2"
  "$PYTHON_BIN" - "$file" "$expr" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expr = sys.argv[2]
if not eval(expr, {"data": data}):
    raise SystemExit(f"json assertion failed: {expr}")
PY
}

PYTHON_BIN="$(command -v python || command -v python3 || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "python is required for this test" >&2
  exit 1
fi

FAKE_BIN="$TMP/bin"
HOME_DIR="$TMP/home"
OUT_DIR="$TMP/out"
PROJECT="$HOME_DIR/Documents/visual"
THREAD_ID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
mkdir -p "$FAKE_BIN" "$HOME_DIR/.codex/sessions" "$OUT_DIR" "$PROJECT"

cat > "$FAKE_BIN/rsync" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    --exclude-from=*) ;;
    -*) ;;
    *) args+=("$arg") ;;
  esac
done
src="${args[$((${#args[@]} - 2))]}"
dst="${args[$((${#args[@]} - 1))]}"
mkdir -p "$dst"
cp -a "${src%/}/." "$dst/"
SH
chmod +x "$FAKE_BIN/rsync"

cat > "$FAKE_BIN/zip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    *) touch "$arg"; exit 0 ;;
  esac
done
SH
chmod +x "$FAKE_BIN/zip"

cat > "$FAKE_BIN/python3" <<SH
#!/usr/bin/env bash
exec "$PYTHON_BIN" "\$@"
SH
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/shasum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-a" && "${2:-}" == "256" ]]; then
  shift 2
fi
sha256sum "$@"
SH
chmod +x "$FAKE_BIN/shasum"

cat > "$HOME_DIR/.codex/sessions/$THREAD_ID.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$THREAD_ID","thread_name":"Visual Mac","cwd":"$PROJECT"}}
{"type":"event","payload":{"message":{"role":"user","content":"open $PROJECT"}}}
EOF
cat > "$HOME_DIR/.codex/session_index.jsonl" <<EOF
{"id":"$THREAD_ID","thread_name":"Visual Mac","updated_at":"2026-06-19T00:00:00Z"}
EOF
cat > "$HOME_DIR/.codex/.codex-global-state.json" <<EOF
{"electron-saved-workspace-roots":["$PROJECT"],"project-order":["$PROJECT"],"active-workspace-roots":["$PROJECT"],"thread-workspace-root-hints":{"$THREAD_ID":"$PROJECT"}}
EOF
echo "project readme" > "$PROJECT/README.md"

"$PYTHON_BIN" - "$HOME_DIR/.codex/state_5.sqlite" "$THREAD_ID" "$PROJECT" "$HOME_DIR/.codex/sessions/$THREAD_ID.jsonl" <<'PY'
import sqlite3
import sys

db, tid, cwd, rollout = sys.argv[1:5]
con = sqlite3.connect(db)
con.execute(
    "create table threads (id text primary key, cwd text, rollout_path text, title text, updated_at text, archived integer, has_user_event integer, preview text)"
)
con.execute(
    "insert into threads values (?,?,?,?,?,?,?,?)",
    (tid, cwd, rollout, "Visual Mac", "2026-06-19T00:00:00Z", 0, 1, "visual"),
)
con.commit()
con.close()
PY

PATH="$FAKE_BIN:$PATH" HOME="$HOME_DIR" bash "$SCRIPT" --out "$OUT_DIR" --project "$PROJECT" >/tmp/codex-rehome-mac-packager-test.log

STAGE="$(find "$OUT_DIR" -maxdepth 1 -type d -name 'Codex-Migration-Mac-Source-*' | head -n 1)"
if [[ -z "$STAGE" ]]; then
  echo "package stage was not created" >&2
  cat /tmp/codex-rehome-mac-packager-test.log >&2 || true
  exit 1
fi

assert_file "$STAGE/SHA256SUMS.txt"
assert_not_contains "$STAGE/SHA256SUMS.txt" "./SHA256SUMS.txt"

assert_file "$STAGE/metadata/path_map.json"
assert_file "$STAGE/metadata/thread_index_export.json"
assert_file "$STAGE/metadata/project_ui_registry_export.json"
assert_file "$STAGE/metadata/selected_chats.json"

assert_json_value "$STAGE/metadata/path_map.json" "data.get('schema') == 3 and data.get('source_os') == 'Mac' and len(data.get('projects', [])) == 1"
assert_json_value "$STAGE/metadata/thread_index_export.json" "data.get('schema') == 3 and data.get('source_os') == 'Mac' and len(data.get('threads', [])) == 1"
assert_json_value "$STAGE/metadata/project_ui_registry_export.json" "data.get('schema') == 3 and data.get('source_os') == 'Mac' and data.get('project_registry', {}).get('thread-workspace-root-hints')"
assert_json_value "$STAGE/MANIFEST.json" "data.get('source_os') == 'Mac' and data.get('package_schema_version') == 3 and data.get('counts', {}).get('thread_index_export') == 1"

echo "mac_packager_metadata_test passed"
