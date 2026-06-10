#!/usr/bin/env bash
# her-web release check: read-only release report for production deploys.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-}"
TARGET_REF="${2:-}"
MODE="${MODE:-normal}"
JSON_OUT=""
REPORT_DIR="${REPORT_DIR:-/tmp/her-web-release}"
SERVER="${SERVER:-ubuntu@192.144.187.174}"
SERVICE="${SERVICE:-her-herweb-a8y5ka}"
SSH_BIN="${SSH_BIN:-/usr/bin/ssh}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"
REQUIRED_COMMITS=()
FIX_INTENT=""
MIGRATION_REPORT=""

source "$SCRIPT_DIR/migration-report-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  release-check.sh <repo> <target-ref> --json-out <path> [--mode normal|emergency] [--required-commit <sha>] [--fix-intent <keyword>] [--migration-report <path>]

Read-only. Generates a human summary and a machine JSON release report.
EOF
}

if [[ -z "$REPO" || -z "$TARGET_REF" ]]; then
  usage >&2
  exit 2
fi
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out)
      JSON_OUT="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-normal}"
      shift 2
      ;;
    --required-commit)
      REQUIRED_COMMITS+=("${2:-}")
      shift 2
      ;;
    --fix-intent)
      FIX_INTENT="${2:-}"
      shift 2
      ;;
    --migration-report)
      MIGRATION_REPORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$JSON_OUT" ]]; then
  mkdir -p "$REPORT_DIR"
  JSON_OUT="$REPORT_DIR/report.json"
fi

REPO="$(cd "$REPO" && pwd)"
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repo: $REPO" >&2
  exit 1
fi

TARGET_SHA="$(git -C "$REPO" rev-parse --verify "${TARGET_REF}^{commit}")"
TARGET_TREE_SHA="$(git -C "$REPO" rev-parse "${TARGET_SHA}^{tree}")"
TARGET_SHORT="$(git -C "$REPO" rev-parse --short "$TARGET_SHA")"
REMOTE_MAIN_SHA="$(git -C "$REPO" ls-remote origin refs/heads/main | awk '{print $1}')"
REMOTE_SUYUAN_SHA="$(git -C "$REPO" ls-remote origin refs/heads/suyuan 2>/dev/null | awk '{print $1}' || true)"
LOCAL_SUYUAN_SHA="$(git -C "$REPO" rev-parse --verify suyuan 2>/dev/null || true)"
TRACKED_DIRTY="$(git -C "$REPO" status --porcelain --untracked-files=no)"
UNTRACKED_SOURCE="$(git -C "$REPO" ls-files --others --exclude-standard -- 'src/**' 'app/**' 'components/**' 'lib/**' 'config/**' 'scripts/**' 'public/**' || true)"

REPORT_ID="her-web-${TARGET_SHORT}-${NOW_EPOCH}"
GENERATED_AT="$(date -u -r "$NOW_EPOCH" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
EXPIRES_AT="$(date -u -r "$((NOW_EPOCH + 900))" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
BLOCKERS="$TMP_DIR/blockers.jsonl"
WARNINGS="$TMP_DIR/warnings.jsonl"
HIGH_RISK="$TMP_DIR/high-risk.txt"
SMOKE="$TMP_DIR/smoke.jsonl"
: > "$BLOCKERS"
: > "$WARNINGS"
: > "$HIGH_RISK"
: > "$SMOKE"

json_line() {
  jq -nc --arg code "$1" --arg message "$2" --arg evidence "$3" \
    '{code:$code,message:$message,evidence:($evidence|split("\n")|map(select(length>0)))}'
}

add_blocker() { json_line "$1" "$2" "${3:-}" >> "$BLOCKERS"; }
add_warning() { json_line "$1" "$2" "${3:-}" >> "$WARNINGS"; }
add_smoke() {
  jq -nc --arg id "$1" --arg label "$2" --arg reason "$3" '{id:$id,label:$label,reason:$reason}' >> "$SMOKE"
}

prod_ssh() {
  if [[ "${HER_WEB_RELEASE_FAKE_PROD:-0}" == "1" ]]; then
    return 1
  fi
  "$SSH_BIN" -n "$SERVER" "$1" 2>/dev/null
}

SERVICE_IMAGE="$(prod_ssh "sudo docker service inspect $SERVICE --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'" || true)"
CONTAINER_ID="$(prod_ssh "sudo docker ps --filter label=com.docker.swarm.service.name=$SERVICE --format '{{.ID}}' | head -1" || true)"
RUNNING_IMAGE="$(prod_ssh "if [ -n '$CONTAINER_ID' ]; then sudo docker inspect --format '{{.Image}}' '$CONTAINER_ID'; fi" || true)"
TASK_ID="$(prod_ssh "sudo docker service ps $SERVICE --filter desired-state=running --format '{{.ID}}' | head -1" || true)"
CURRENT_JSON="$(prod_ssh "cat /home/ubuntu/her-web-release/current.json" || true)"
CURRENT_JSON_SHA=""
PRODUCTION_COMMIT=""
METADATA_TRUSTED="false"
BOOTSTRAP="false"
NON_MAIN_OVERRIDE="false"
REQUIRED_FROM_METADATA=()
ROLLBACK_EXECUTABLE="false"
CURRENT_METADATA_PRESENT="false"

if [[ -n "$SERVICE_IMAGE" ]] && prod_ssh "sudo docker image inspect '$SERVICE_IMAGE' >/dev/null 2>&1"; then
  ROLLBACK_EXECUTABLE="true"
else
  add_blocker "ROLLBACK_IMAGE_MISSING" "当前生产镜像不在服务器本地，无法证明下一次发布可回滚。" "serviceImage=$SERVICE_IMAGE"
fi

if [[ -n "$CURRENT_JSON" ]] && echo "$CURRENT_JSON" | jq empty >/dev/null 2>&1; then
  CURRENT_METADATA_PRESENT="true"
  CURRENT_JSON_SHA="$(prod_ssh "shasum -a 256 /home/ubuntu/her-web-release/current.json | cut -d ' ' -f1" || true)"
  PRODUCTION_COMMIT="$(echo "$CURRENT_JSON" | jq -r '.commit // empty')"
  METADATA_TRUSTED="$(echo "$CURRENT_JSON" | jq -r '.metadataTrusted // false')"
  BOOTSTRAP="$(echo "$CURRENT_JSON" | jq -r '.bootstrap // false')"
  NON_MAIN_OVERRIDE="$(echo "$CURRENT_JSON" | jq -r '.nonMainOverride // false')"
  while IFS= read -r sha; do
    [[ -n "$sha" ]] && REQUIRED_FROM_METADATA+=("$sha")
  done < <(echo "$CURRENT_JSON" | jq -r '.requiredHotfixCommits[]?')
else
  add_blocker "PRODUCTION_METADATA_MISSING" "生产 metadata 缺失，无法机器证明当前线上 commit。" "server=$SERVER"$'\n'"service=$SERVICE"
fi

for sha in "${REQUIRED_FROM_METADATA[@]}"; do
  REQUIRED_COMMITS+=("$sha")
done

if [[ "$MODE" == "normal" && "$TARGET_SHA" != "$REMOTE_MAIN_SHA" ]]; then
  add_blocker "TARGET_NOT_REMOTE_MAIN" "正常发布目标不是当前远端 origin/main。" "target=$TARGET_SHA"$'\n'"remoteOriginMain=$REMOTE_MAIN_SHA"
fi

if [[ -n "$TRACKED_DIRTY" ]]; then
  add_blocker "TRACKED_WORKTREE_DIRTY" "目标工作区有未提交的已跟踪文件。" "$TRACKED_DIRTY"
fi

if [[ -n "$UNTRACKED_SOURCE" ]]; then
  add_warning "UNTRACKED_SOURCE" "发现未跟踪源码文件；git archive 不会带它们上线。" "$UNTRACKED_SOURCE"
fi

HOTFIX_PROOF_OK="true"
for sha in "${REQUIRED_COMMITS[@]}"; do
  if [[ -z "$sha" ]]; then
    continue
  fi
  if ! git -C "$REPO" merge-base --is-ancestor "$sha" "$TARGET_SHA" >/dev/null 2>&1; then
    HOTFIX_PROOF_OK="false"
    add_blocker "REQUIRED_HOTFIX_MISSING" "目标版本不包含必须保留的线上热修 commit。" "required=$sha"$'\n'"target=$TARGET_SHA"
  fi
done

if [[ "$CURRENT_METADATA_PRESENT" == "true" && "$METADATA_TRUSTED" != "true" ]]; then
  if [[ "${#REQUIRED_COMMITS[@]}" -eq 0 || "$HOTFIX_PROOF_OK" != "true" ]]; then
    add_blocker "PRODUCTION_METADATA_UNTRUSTED" "当前生产版本记录不是机器可信状态，且没有完整 requiredHotfixCommits 证明。" "metadataTrusted=$METADATA_TRUSTED"$'\n'"bootstrap=$BOOTSTRAP"
  else
    add_warning "BOOTSTRAP_METADATA_ACCEPTABLE_WITH_HOTFIX_PROOF" "当前生产 metadata 来自 bootstrap，但 target 已包含 requiredHotfixCommits。" "metadataTrusted=$METADATA_TRUSTED"
  fi
fi

if [[ -n "$PRODUCTION_COMMIT" ]] && git -C "$REPO" cat-file -e "${PRODUCTION_COMMIT}^{commit}" 2>/dev/null; then
  if ! git -C "$REPO" merge-base --is-ancestor "$PRODUCTION_COMMIT" "$TARGET_SHA" >/dev/null 2>&1; then
    REMOVED_COMMITS="$(git -C "$REPO" log --oneline "$TARGET_SHA..$PRODUCTION_COMMIT" || true)"
    if [[ "$NON_MAIN_OVERRIDE" == "true" && "${#REQUIRED_COMMITS[@]}" -gt 0 && "$HOTFIX_PROOF_OK" == "true" ]]; then
      add_warning "NON_MAIN_PRODUCTION_SUPERSEDED_BY_REQUIRED_COMMITS" "当前生产来自非 main 紧急发布；目标版本不是当前生产 commit 的后代，但已包含明确确认的保底修复 commits。" "$REMOVED_COMMITS"
    else
      add_blocker "TARGET_REMOVES_PRODUCTION_COMMITS" "目标版本不是当前生产 commit 的后代，可能抹掉线上已有修复。" "$REMOVED_COMMITS"
    fi
  fi
  DIFF_BASE="$PRODUCTION_COMMIT"
else
  DIFF_BASE="$(git -C "$REPO" rev-parse "${TARGET_SHA}^" 2>/dev/null || echo "$TARGET_SHA")"
fi

CHANGED_FILES="$(git -C "$REPO" diff --name-only "$DIFF_BASE..$TARGET_SHA" || true)"
SCHEMA_DIFF=""
MYSQL_ONLY_DIFF=""
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    src/config/db/schema.ts|src/config/db/schema.postgres.ts|src/config/db/schema.sqlite.ts|drizzle/*|drizzle.config.ts)
      SCHEMA_DIFF+="${file}"$'\n'
      ;;
    src/config/db/schema.mysql.ts)
      MYSQL_ONLY_DIFF+="${file}"$'\n'
      ;;
  esac
done <<< "$CHANGED_FILES"

if [[ -n "$SCHEMA_DIFF" ]]; then
  if [[ -n "$MIGRATION_REPORT" ]]; then
    if migration_report_validate "$MIGRATION_REPORT" "$TARGET_SHA" "$SCHEMA_DIFF"; then
      add_warning "SCHEMA_MIGRATION_CONFIRMED" "检测到 Postgres/schema/drizzle 相关变更，但 migration report 已提供并通过校验。" "$SCHEMA_DIFF"$'\n'"report=$MIGRATION_REPORT"
    else
      add_blocker "SCHEMA_MIGRATION_CHANGED" "检测到 Postgres/schema/drizzle 相关变更；migration report 缺失或无效。" "$SCHEMA_DIFF"$'\n'"report=$MIGRATION_REPORT"
    fi
  else
    add_blocker "SCHEMA_MIGRATION_CHANGED" "检测到 Postgres/schema/drizzle 相关变更；需要单独 migration report。" "$SCHEMA_DIFF"
  fi
elif [[ -n "$MYSQL_ONLY_DIFF" ]]; then
  add_warning "MYSQL_SCHEMA_CHANGED" "schema.mysql.ts 单独变化；当前生产是 Postgres，先记 WARN。" "$MYSQL_ONLY_DIFF"
fi

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    src/core/auth/*|src/core/auth/**|src/modules/entitlements/*|src/modules/entitlements/**|src/modules/invite-codes/*|src/modules/invite-codes/**|src/modules/herclub/*|src/modules/herclub/**|src/modules/api-gateway/*|src/modules/api-gateway/**|src/modules/payment/*|src/modules/payment/**|src/app/*/admin/*|src/app/*/admin/**|src/app/*/settings/*|src/app/*/settings/**|src/app/api/admin/*|src/app/api/admin/**|src/app/api/user/*|src/app/api/user/**|src/app/api/v1/*|src/app/api/v1/**|src/components/app-sidebar.tsx|src/components/app-layout.tsx|src/components/user-menu.tsx|src/config/db/*|drizzle/*|drizzle.config.ts|Dockerfile|.github/workflows/*|package.json|pnpm-lock.yaml|next.config.*|middleware.ts)
      echo "$file" >> "$HIGH_RISK"
      ;;
  esac
done <<< "$CHANGED_FILES"

if [[ -s "$HIGH_RISK" ]]; then
  add_warning "HIGH_RISK_FILES_CHANGED" "本次变更命中高风险路径，需要 smoke 确认。" "$(cat "$HIGH_RISK")"
  if grep -Eq 'src/app/.*/admin|src/components/app-sidebar.tsx|src/components/app-layout.tsx|src/components/user-menu.tsx|src/app/.*/settings' "$HIGH_RISK"; then
    add_smoke "admin-entry" "管理员能进入 /admin，普通用户看不到 admin 入口" "本次变更影响 admin/settings/app shell。"
  fi
  if grep -Eq 'entitlements|herclub|api-gateway|src/app/api/user|src/app/api/v1' "$HIGH_RISK"; then
    add_smoke "entitlement" "测试用户国际模型 / model regions / entitlement 不倒退" "本次变更影响授权、HerClub 或 gateway-facing API。"
  fi
fi

if [[ -n "$REMOTE_SUYUAN_SHA" ]]; then
  git -C "$REPO" fetch --quiet origin "$REMOTE_SUYUAN_SHA" || true
fi
SUYUAN_AHEAD="$(git -C "$REPO" log --oneline "$TARGET_SHA..${REMOTE_SUYUAN_SHA:-$LOCAL_SUYUAN_SHA}" 2>/dev/null || true)"
SUYUAN_HIGH_RISK="$(git -C "$REPO" diff --name-only "$TARGET_SHA..${REMOTE_SUYUAN_SHA:-$LOCAL_SUYUAN_SHA}" 2>/dev/null | grep -E 'src/(core/auth|modules/entitlements|modules/herclub|modules/api-gateway|modules/payment)|src/app/.*/admin|src/app/.*/settings|src/app/api/(admin|user|v1)|src/components/(app-sidebar|app-layout|user-menu)\\.tsx|src/config/db|drizzle' || true)"
if [[ -n "$SUYUAN_HIGH_RISK" ]]; then
  add_warning "SUYUAN_HAS_HIGH_RISK_AHEAD_OF_MAIN" "suyuan 有未进入 main 的高风险业务改动，发布前要确认 main 没漏修复。" "$SUYUAN_HIGH_RISK"
fi

if [[ -z "$SERVICE_IMAGE" || -z "$RUNNING_IMAGE" ]]; then
  add_warning "PRODUCTION_STATE_PARTIAL" "无法完整读取生产 service/running image。" "serviceImage=$SERVICE_IMAGE"$'\n'"runningImage=$RUNNING_IMAGE"
fi

FINGERPRINT="$(printf '%s|%s|%s|%s' "$SERVICE_IMAGE" "$RUNNING_IMAGE" "$TASK_ID" "$CURRENT_JSON_SHA" | shasum -a 256 | awk '{print $1}')"
MIGRATION_REPORT_SUMMARY="null"

if [[ -n "$MIGRATION_REPORT" ]]; then
  if migration_report_validate "$MIGRATION_REPORT" "$TARGET_SHA" "$SCHEMA_DIFF"; then
    MIGRATION_REPORT_SUMMARY="$(migration_report_summary_json "$MIGRATION_REPORT")"
  else
    add_blocker "MIGRATION_REPORT_INVALID" "提供了 migration report，但内容无效或与目标版本不匹配。" "$MIGRATION_REPORT"
  fi
fi

BLOCKERS_JSON="$(jq -s . "$BLOCKERS")"
WARNINGS_JSON="$(jq -s . "$WARNINGS")"
HIGH_RISK_JSON="$(jq -R -s 'split("\n")|map(select(length>0))' "$HIGH_RISK")"
SMOKE_JSON="$(jq -s . "$SMOKE")"

DECISION="READY"
if [[ "$(echo "$BLOCKERS_JSON" | jq 'length')" -gt 0 ]]; then
  DECISION="BLOCKED"
elif [[ "$(echo "$WARNINGS_JSON" | jq 'length')" -gt 0 || "$(echo "$SMOKE_JSON" | jq 'length')" -gt 0 ]]; then
  DECISION="WARN"
fi

mkdir -p "$(dirname "$JSON_OUT")"
REPORT_TMP="$TMP_DIR/report.nohash.json"
jq -n \
  --arg reportId "$REPORT_ID" \
  --arg generatedAt "$GENERATED_AT" \
  --arg expiresAt "$EXPIRES_AT" \
  --arg repoRoot "$REPO" \
  --arg targetRef "$TARGET_REF" \
  --arg targetSha "$TARGET_SHA" \
  --arg targetTreeSha "$TARGET_TREE_SHA" \
  --arg originMainSha "$REMOTE_MAIN_SHA" \
  --arg decision "$DECISION" \
  --arg service "$SERVICE" \
  --arg serviceImage "$SERVICE_IMAGE" \
  --arg runningImage "$RUNNING_IMAGE" \
  --arg taskId "$TASK_ID" \
  --arg currentJsonSha256 "$CURRENT_JSON_SHA" \
  --arg productionCommit "$PRODUCTION_COMMIT" \
  --arg metadataTrusted "$METADATA_TRUSTED" \
  --arg bootstrap "$BOOTSTRAP" \
  --arg nonMainOverride "$NON_MAIN_OVERRIDE" \
  --arg fingerprint "$FINGERPRINT" \
  --arg rollbackExecutable "$ROLLBACK_EXECUTABLE" \
  --arg suyuanSha "$LOCAL_SUYUAN_SHA" \
  --arg originSuyuanSha "$REMOTE_SUYUAN_SHA" \
  --arg fixIntent "$FIX_INTENT" \
  --argjson blocking "$BLOCKERS_JSON" \
  --argjson warnings "$WARNINGS_JSON" \
  --argjson highRiskFiles "$HIGH_RISK_JSON" \
  --argjson requiredSmoke "$SMOKE_JSON" \
  --arg migrationReportPath "$MIGRATION_REPORT" \
  --argjson migrationReport "$MIGRATION_REPORT_SUMMARY" \
  --argjson commitsAheadOfMain "$(printf '%s\n' "$SUYUAN_AHEAD" | jq -R -s 'split("\n")|map(select(length>0))')" \
  --argjson highRiskFilesAheadOfMain "$(printf '%s\n' "$SUYUAN_HIGH_RISK" | jq -R -s 'split("\n")|map(select(length>0))')" \
  '{
    reportVersion: 1,
    reportId: $reportId,
    reportHash: "",
    generatedAt: $generatedAt,
    expiresAt: $expiresAt,
    repoRoot: $repoRoot,
    worktreePath: $repoRoot,
    scriptVersion: "release-check-v1",
    targetRef: $targetRef,
    targetSha: $targetSha,
    targetTreeSha: $targetTreeSha,
    originMainSha: $originMainSha,
    fixIntent: $fixIntent,
    decision: $decision,
    blocking: $blocking,
    warnings: $warnings,
    highRiskFiles: $highRiskFiles,
    requiredSmoke: $requiredSmoke,
    migrationReportPath: ($migrationReportPath // null),
    migrationReport: $migrationReport,
    suyuanComparison: {
      suyuanSha: ($suyuanSha // null),
      originSuyuanSha: ($originSuyuanSha // null),
      commitsAheadOfMain: $commitsAheadOfMain,
      highRiskFilesAheadOfMain: $highRiskFilesAheadOfMain,
      businessRiskSummary: []
    },
    checkedProductionState: {
      service: $service,
      serviceImage: $serviceImage,
      runningImage: $runningImage,
      taskId: $taskId,
      currentJsonSha256: $currentJsonSha256,
      productionCommit: ($productionCommit // null),
      metadataTrusted: ($metadataTrusted == "true"),
      bootstrap: ($bootstrap == "true"),
      nonMainOverride: ($nonMainOverride == "true"),
      fingerprint: $fingerprint
    },
    envSummary: {
      production: {
        presentKeys: [],
        missingRequiredKeys: [],
        publicUrlClass: "unknown",
        databaseClass: "unknown"
      },
      localProdSnapshot: {
        metadataPresent: false,
        snapshotAgeHours: null,
        databaseClass: "unknown",
        gatewayClass: "unknown"
      }
    },
    rollbackTarget: {
      image: $serviceImage,
      commit: ($productionCommit // null),
      source: "current-service-image",
      executable: ($rollbackExecutable == "true")
    }
  }' > "$REPORT_TMP"

REPORT_HASH="$(jq -S -c 'del(.reportHash)' "$REPORT_TMP" | shasum -a 256 | awk '{print $1}')"
jq --arg hash "$REPORT_HASH" '.reportHash = $hash' "$REPORT_TMP" > "$JSON_OUT"

echo "结果：$DECISION"
echo ""
case "$DECISION" in
  BLOCKED)
    echo "不会部署，因为："
    jq -r '.blocking[] | "- " + .message' "$JSON_OUT"
    ;;
  WARN)
    echo "需要你确认后才能上线，因为："
    jq -r '.warnings[] | "- " + .message' "$JSON_OUT"
    if [[ "$(jq '.requiredSmoke | length' "$JSON_OUT")" -gt 0 ]]; then
      echo ""
      echo "部署前必须确认 smoke："
      jq -r '.requiredSmoke[] | "- " + .label' "$JSON_OUT"
      echo ""
      echo "继续需要：ACCEPT_RELEASE_REPORT=$REPORT_ID:$REPORT_HASH + CONFIRM_SMOKE=$(jq -r '.requiredSmoke[].id' "$JSON_OUT" | paste -sd, -)"
    else
      echo ""
      echo "继续需要：ACCEPT_RELEASE_REPORT=$REPORT_ID:$REPORT_HASH"
    fi
    ;;
  READY)
    echo "可以进入 release.sh 后续步骤。"
    ;;
esac
echo ""
echo "report: $JSON_OUT"
