#!/usr/bin/env bash

set -euo pipefail

TAG="${1:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
OUTPUT_FILE="${2:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
REPOSITORY_URL="${3:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
HIGHLIGHTS="${RELEASE_HIGHLIGHTS:-}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo "Invalid tag: $TAG" >&2
  exit 1
fi

if [[ -z "$(printf '%s' "$HIGHLIGHTS" | tr -d '[:space:]|')" ]]; then
  echo "RELEASE_HIGHLIGHTS must contain at least one user-facing change." >&2
  exit 1
fi

target_ref="HEAD"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  target_ref="$TAG"
fi
previous_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$target_ref^" 2>/dev/null || true)"

if [[ -n "$previous_tag" ]]; then
  changelog_url="$REPOSITORY_URL/compare/$previous_tag...$TAG"
  changelog_label="查看 $previous_tag 到 $TAG 的完整变更"
else
  changelog_url="$REPOSITORY_URL/commits/$TAG"
  changelog_label="查看 $TAG 的完整提交记录"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  printf '## 关于 CodexVista\n\n'
  printf 'CodexVista（原 SpendScope）是一款原生 macOS 菜单栏应用，将本机 Codex CLI 与 Desktop 的使用记录整理为额度摘要和详细看板，无需额外登录，不上传使用数据。\n\n'
  printf '## 本版本更新\n\n'

  normalized_highlights="${HIGHLIGHTS//|/$'\n'}"
  while IFS= read -r highlight || [[ -n "$highlight" ]]; do
    highlight="$(printf '%s' "$highlight" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    highlight="${highlight#- }"
    if [[ -n "$highlight" ]]; then
      printf -- '- %s\n' "$highlight"
    fi
  done < <(printf '%s' "$normalized_highlights")

  cat <<EOF

## 功能全览

- **额度与提醒**：状态栏或刘海下方展示 7 天额度和重置倒计时，菜单栏弹窗提供近 7 天额度变化曲线，并支持剩余额度 20%、10%、5% 本机提醒。
- **Token 与趋势**：今日、7 日、30 日、累计及可选订阅周期统计，包含四类 Token、用量趋势与日历。
- **项目与调用**：项目、任务、回复下钻，查看 AI 工作时长、模型及 Skills / Tools 调用；子代理用量归并到对应主任务。
- **模型费用**：按公开 API 标准价格展示等值估算，参考价模型明确标记，不冒充 Codex 订阅账单。
- **六款皮肤**：经典、水墨、青瓷、暮霞、未来科技和仙侠，统一覆盖看板、状态栏、刘海摘要、弹窗与设置。
- **本地优先**：增量导入、去重、手动刷新与全量重建；不采集提示词、回复正文或认证文件内容。

## 下载与安装

1. 在下方 **Assets** 下载 \`CodexVista-macOS-unsigned.dmg\`。
2. 打开 DMG，将 CodexVista 拖入“应用程序”文件夹。
3. 首次启动请在 Finder 中右键 CodexVista，选择“打开”，再确认一次。

## 从 SpendScope 升级

- 旧版内置下载器使用旧安装包文件名，请从本页手动下载一次 CodexVista 安装包，并先退出旧版应用。
- 首次启动在新版数据库不存在时接续旧版统计，合并支持的偏好且保留新版已有设置；旧数据库保留，不修改 Codex 原始记录。
- 确认新版正常后可移除旧的 SpendScope.app，避免同时运行；不要删除旧数据目录作为安装步骤。通知权限需为新应用重新授权。

## 系统与芯片支持

- macOS 14 或更高版本。
- Universal Binary，同时支持 Apple 芯片（arm64）和 Intel 芯片（x86_64）。

## 未签名版本首次打开

当前安装包尚未使用 Apple Developer ID 签名和公证。若系统提示应用“已损坏”，请先确认 DMG 来自本仓库的 GitHub Releases，再在终端执行：

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/CodexVista.app
\`\`\`

不要对来源不明的 App 执行此命令。

## 附件说明

- \`CodexVista-macOS-unsigned.dmg\`：macOS 安装包。
- \`CodexVista-macOS-unsigned.dmg.sha256\`：安装包 SHA-256 校验文件。
- \`Source code (zip)\` / \`Source code (tar.gz)\`：GitHub 根据本版本标签自动生成的源码包。

下载 DMG 和校验文件后，可在同一目录执行：

\`\`\`bash
shasum -a 256 -c CodexVista-macOS-unsigned.dmg.sha256
\`\`\`

## 已知限制

- 当前安装包未签名、未公证，首次启动需要手动确认。
- CodexVista 仅统计本机 Codex 记录，不同步其他设备或服务端历史。
- 模型费用仅为 API 标准价下的等值估算，不代表 Codex 实际账单；暂不提供账单对账或 API Key 实际消费分析。

## 完整变更

[$changelog_label]($changelog_url)
EOF
} > "$OUTPUT_FILE"
