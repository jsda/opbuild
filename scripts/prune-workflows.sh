#!/usr/bin/env bash

set -Eeuo pipefail

#
# 必需环境变量
#
: "${ARTIFACT_RETENTION_DAYS:?必须设置 ARTIFACT_RETENTION_DAYS}"

#
# 可选环境变量
#
DRY_RUN="${DRY_RUN:-0}"

#
# GitHub Actions Step Summary
#
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"

#
# 当前仓库
#
REPO="${GITHUB_REPOSITORY:-}"

if [[ -z "$REPO" ]]; then
  echo "❌ GITHUB_REPOSITORY 未设置"
  exit 1
fi

#
# 日志函数
#
log() {
  echo -e "$1"

  if [[ -n "$SUMMARY_FILE" ]]; then
    echo -e "$1" >> "$SUMMARY_FILE"
  fi
}

#
# Header
#
log "## 🧹 Workflow 清理报告"
log ""

log "- 仓库：$REPO"
log "- 保留天数：$ARTIFACT_RETENTION_DAYS"
log "- DRY_RUN：$DRY_RUN"
log ""

echo "----------------------------------------"
echo "📦 GitHub CLI 信息"

gh --version || true

echo "----------------------------------------"

#
# 权限检测
#
echo "🔐 检查 GitHub 登录状态..."

if ! gh auth status >/dev/null 2>&1; then
  echo "❌ GitHub CLI 未登录"
  exit 1
fi

echo "✅ GitHub CLI 已登录"

#
# 截止时间
#
cutoff_date=$(
  date -u -d "$ARTIFACT_RETENTION_DAYS days ago" +"%Y-%m-%dT%H:%M:%SZ"
)

cutoff_ts=$(
  date -d "$cutoff_date" +%s
)

log "- 截止时间：\`$cutoff_date\`"
log ""

echo "----------------------------------------"
echo "📡 正在获取 workflow 运行记录..."

#
# 获取 workflow runs
#
mapfile -t runs < <(
  gh run list \
    --limit 200 \
    --json databaseId,createdAt,status,name \
    --jq '
      .[]
      | select(.status == "completed")
      | "\(.databaseId)|\(.createdAt)|\(.name)"
    '
)

total=${#runs[@]}

echo "获取到已完成运行数：$total"

echo "----------------------------------------"

#
# 统计变量
#
keep_count=0
delete_count=0
candidate_delete_count=0
error_count=0

#
# 输出记录
#
deleted_lines=()
kept_lines=()
failed_lines=()

#
# 遍历 workflow runs
#
for entry in "${runs[@]}"; do

  IFS='|' read -r run_id created_at workflow_name <<< "$entry"

  workflow_name="${workflow_name:-unknown}"

  created_ts=$(
    date -d "$created_at" +%s
  )

  #
  # 判断是否过期
  #
  if (( created_ts < cutoff_ts )); then

    ((++candidate_delete_count))

    echo "🗑️ 删除候选 | $run_id | $workflow_name | $created_at"

    #
    # DRY RUN
    #
    if [[ "$DRY_RUN" == "1" ]]; then

      echo "   ↳ DRY_RUN 模式，跳过实际删除"

      deleted_lines+=(
        "- [DRY_RUN] $run_id | $workflow_name | $created_at"
      )

      continue
    fi

    #
    # 删除 workflow run
    #
    if gh api \
      --silent \
      -X DELETE \
      "repos/$REPO/actions/runs/$run_id"
    then

      echo "   ✔ 删除成功：$run_id"

      ((++delete_count))

      deleted_lines+=(
        "- $run_id | $workflow_name | $created_at"
      )

    else

      echo "   ❌ 删除失败：$run_id"

      ((++error_count))

      failed_lines+=(
        "- $run_id | $workflow_name | $created_at"
      )

    fi

  else

    echo "✅ 保留      | $run_id | $workflow_name | $created_at"

    ((++keep_count))

    kept_lines+=(
      "- $run_id | $workflow_name | $created_at"
    )

  fi

done

echo "----------------------------------------"

echo "📊 统计结果"
echo "  总计扫描：$total"
echo "  保留数量：$keep_count"
echo "  删除候选：$candidate_delete_count"
echo "  实际删除：$delete_count"
echo "  失败数量：$error_count"

#
# Summary
#
log "## 📊 统计结果"
log ""

log "| 项目 | 数量 |"
log "|------|------|"
log "| 总计扫描 | $total |"
log "| 保留数量 | $keep_count |"
log "| 删除候选 | $candidate_delete_count |"
log "| 实际删除 | $delete_count |"
log "| 失败数量 | $error_count |"

log ""

if [[ "$DRY_RUN" == "1" ]]; then
  log "⚠️ 当前为 DRY_RUN 模式，未执行实际删除"
  log ""
fi

#
# 删除记录
#
if (( candidate_delete_count > 0 )); then

  log "## 🗑️ 删除记录"
  log ""

  if [[ -n "$SUMMARY_FILE" ]]; then
    printf "%s\n" "${deleted_lines[@]}" >> "$SUMMARY_FILE"
  fi

  log ""

else

  log "ℹ️ 没有需要删除的运行记录"
  log ""

fi

#
# 删除失败记录
#
if (( error_count > 0 )); then

  log "## ❌ 删除失败记录"
  log ""

  if [[ -n "$SUMMARY_FILE" ]]; then
    printf "%s\n" "${failed_lines[@]}" >> "$SUMMARY_FILE"
  fi

  log ""

fi

#
# 保留记录
#
if (( keep_count > 0 )); then

  log "<details><summary>保留的运行记录（展开）</summary>"
  log ""

  if [[ -n "$SUMMARY_FILE" ]]; then
    printf "%s\n" "${kept_lines[@]}" >> "$SUMMARY_FILE"
  fi

  log ""
  log "</details>"

fi

log ""

#
# 最终结果
#
if [[ "$DRY_RUN" == "1" ]]; then

  log "🧪 DRY_RUN 完成，共发现 $candidate_delete_count 个可清理 workflow"

else

  log "✅ 已成功清理 $delete_count 个 workflow"

fi

if (( error_count > 0 )); then

  log "❌ 清理过程中存在失败"

  exit 1

fi

echo "✅ 清理完成"