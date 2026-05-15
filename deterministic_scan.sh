#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"

emit() {
  # $1 = type
  # $2 = message
  jq -nc --arg type "$1" --arg msg "$2" '{type:$type, msg:$msg}'
}

emit_kv() {
  # $1 = type
  # $2 = key
  # $3 = value
  jq -nc --arg type "$1" --arg key "$2" --arg val "$3" '{type:$type, key:$key, value:$val}'
}

emit "info" "Starting Quantum Badger deterministic scan"

###############################################
# 1. File Inventory
###############################################
emit "section" "file_inventory"

# Use git ls-files if in a git repo to focus on tracked files,
# otherwise fall back to find excluding .git
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files | sort | while read -r f; do
    checksum=$(shasum "$f" | awk '{print $1}')
    emit_kv "file" "$f" "$checksum"
  done
else
  find "$REPO_ROOT" -type f -not -path '*/.*' | sort | while read -r f; do
    checksum=$(shasum "$f" | awk '{print $1}')
    # Make path relative to REPO_ROOT for portability
    rel_f=${f#$REPO_ROOT/}
    emit_kv "file" "$rel_f" "$checksum"
  done
fi

###############################################
# 2. Swift Surface Scan
###############################################
emit "section" "swift_surface"

find "$REPO_ROOT" -name "*.swift" -not -path '*/.*' | while read -r f; do
    # Detect unimplemented functions
    grep -nE "fatalError|TODO|FIXME|#warning" "$f" | while read -r line; do
        rel_f=${f#$REPO_ROOT/}
        emit_kv "swift_issue" "$rel_f" "$line"
    done || true

    # Detect empty function bodies
    grep -nE "func [A-Za-z0-9_]+\([^)]*\)\s*\{\s*\}" "$f" | while read -r line; do
        rel_f=${f#$REPO_ROOT/}
        emit_kv "swift_empty_func" "$rel_f" "$line"
    done || true
done

###############################################
# 3. MLX / Model Service Surface
###############################################
emit "section" "mlx_surface"

grep -RIn --exclude-dir=".git" "MLX" "$REPO_ROOT" | while read -r line; do
    # Make paths relative
    rel_line=${line#$REPO_ROOT/}
    emit_kv "mlx_usage" "mlx" "$rel_line"
done || true

grep -RIn --exclude-dir=".git" "Qwen" "$REPO_ROOT" | while read -r line; do
    # Make paths relative
    rel_line=${line#$REPO_ROOT/}
    emit_kv "model_reference" "qwen" "$rel_line"
done || true

###############################################
# 4. SQLite Schema Scan
###############################################
emit "section" "sqlite_schema"

find "$REPO_ROOT" -name "*.db" -not -path '*/.*' | while read -r db; do
    schema=$(sqlite3 "$db" .schema 2>/dev/null || echo "")
    rel_db=${db#$REPO_ROOT/}
    emit_kv "sqlite_schema" "$rel_db" "$schema"
done

###############################################
# 5. Unsafe Pattern Detection
###############################################
emit "section" "unsafe_patterns"

find "$REPO_ROOT" -name "*.swift" -not -path '*/.*' | while read -r f; do
    grep -nE "try!|force unwrap|DispatchQueue\.global" "$f" | while read -r line; do
        rel_f=${f#$REPO_ROOT/}
        emit_kv "unsafe_pattern" "$rel_f" "$line"
    done || true
done

###############################################
# 6. Buildability Check
###############################################
emit "section" "build_check"

if command -v swift >/dev/null 2>&1; then
  if swift build --configuration debug >/tmp/build.log 2>&1; then
    emit "build" "success"
  else
    emit_kv "build" "failure" "$(cat /tmp/build.log || echo 'Build failed but log is empty')"
  fi
else
  emit_kv "build" "skipped" "swift binary not found"
fi

###############################################
# 7. Contract Surface Extraction
###############################################
emit "section" "contract_surface"

grep -RIn --exclude-dir=".git" "protocol " "$REPO_ROOT" | while read -r line; do
    rel_line=${line#$REPO_ROOT/}
    emit_kv "protocol" "swift" "$rel_line"
done || true

grep -RIn --exclude-dir=".git" "struct " "$REPO_ROOT" | grep -E "Request|Response|Model|Memory" | while read -r line; do
    rel_line=${line#$REPO_ROOT/}
    emit_kv "contract_struct" "swift" "$rel_line"
done || true

###############################################
# 8. P0–P5 Classification Stub
###############################################
emit "section" "classification_stub"

emit_kv "classification_rule" "P0" "Build failure, missing core subsystem, or crash-on-start"
emit_kv "classification_rule" "P1" "Broken contract surface or missing required implementation"
emit_kv "classification_rule" "P2" "Unsafe patterns or nondeterministic behavior"
emit_kv "classification_rule" "P3" "Missing tests or incomplete coverage"
emit_kv "classification_rule" "P4" "Performance or maintainability issues"
emit_kv "classification_rule" "P5" "Cosmetic or documentation issues"

emit "info" "Scan complete"
