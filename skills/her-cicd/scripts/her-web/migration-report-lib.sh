#!/usr/bin/env bash

MIGRATION_REPORT_REQUIRED_CHECK_KEYS=(
  "user.real_name"
  "user.wechat_id"
  "invite_code.balance_cents"
  "invite_code.is_hclub"
  "admin_user_note"
  "usage_record"
  "user_gateway.indexes"
  "rbac.finance_invite"
)

migration_report_validate() {
  local report_path="${1:-}"
  local expected_target_sha="${2:-}"
  local expected_changed_files="${3:-}"
  local errors=()

  if [[ -z "$report_path" ]]; then
    echo "migration report path is empty" >&2
    return 1
  fi

  if [[ ! -f "$report_path" ]]; then
    echo "migration report does not exist: $report_path" >&2
    return 1
  fi

  if ! jq empty "$report_path" >/dev/null 2>&1; then
    echo "migration report is not valid JSON: $report_path" >&2
    return 1
  fi

  if ! jq -e '
    type == "object" and
    (.targetSha | type == "string" and length > 0) and
    (.baseRef | type == "string" and length > 0) and
    (.databaseProvider | type == "string" and length > 0) and
    (.databaseName | type == "string" and length > 0) and
    (.migrationSqlPath | type == "string" and length > 0) and
    (.changedSchemaFiles | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
    (.backupPath | type == "string" and length > 0) and
    (.backupSha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.appliedAt | type == "string" and length > 0) and
    (.appliedBy | type == "string" and length > 0) and
    (.beforeChecks | type == "object") and
    (.afterChecks | type == "object")
  ' "$report_path" >/dev/null; then
    errors+=("missing required top-level fields")
  fi

  if [[ -n "$expected_target_sha" ]]; then
    if ! jq -e --arg sha "$expected_target_sha" '.targetSha == $sha' "$report_path" >/dev/null; then
      errors+=("targetSha does not match expected target: $expected_target_sha")
    fi
  fi

  if ! jq -e '.databaseProvider == "postgres"' "$report_path" >/dev/null; then
    errors+=("databaseProvider must be postgres")
  fi

  local key
  for key in "${MIGRATION_REPORT_REQUIRED_CHECK_KEYS[@]}"; do
    if ! jq -e --arg key "$key" '.beforeChecks | has($key)' "$report_path" >/dev/null; then
      errors+=("beforeChecks missing key: $key")
    fi
    if ! jq -e --arg key "$key" '.afterChecks | has($key)' "$report_path" >/dev/null; then
      errors+=("afterChecks missing key: $key")
    fi
  done

  if [[ -n "$expected_changed_files" ]]; then
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      if ! jq -e --arg file "$file" '.changedSchemaFiles | index($file) != null' "$report_path" >/dev/null; then
        errors+=("changedSchemaFiles missing expected file: $file")
      fi
    done <<< "$expected_changed_files"
  fi

  if [[ "${#errors[@]}" -gt 0 ]]; then
    printf '%s\n' "${errors[@]}" >&2
    return 1
  fi
}

migration_report_summary_json() {
  local report_path="${1:-}"
  jq -c --arg path "$report_path" '{
    path: $path,
    targetSha,
    baseRef,
    databaseProvider,
    databaseName,
    migrationSqlPath,
    backupPath,
    backupSha256,
    appliedAt,
    appliedBy,
    changedSchemaFiles
  }' "$report_path"
}
