#!/bin/bash
# 一键 git push 脚本 - AI 生成语义化 commit 信息
# 用法: ./git-push.sh [可选的额外描述]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查是否有改动
if [[ -z $(git status --porcelain) ]]; then
    echo -e "${GREEN}✓ 工作区干净，无需提交${NC}"
    exit 0
fi

echo -e "${YELLOW}📦 检测到以下改动:${NC}"
git status --short
echo ""

# 暂存所有改动
git add -A

# 获取 diff 内容（限制大小避免 token 过多）
MAX_DIFF_LINES=500
DIFF_CONTENT=$(git diff --cached | head -n $MAX_DIFF_LINES)
DIFF_STAT=$(git diff --cached --stat)

# AI 生成 commit 信息
generate_ai_commit_msg() {
    local extra="$1"

    # 构建 prompt
    local prompt=$(cat <<'PROMPT_EOF'
分析以下 git diff，生成一个简洁的 commit message。

要求：
1. 使用 conventional commits 格式: type: description
2. type 只能是: feat, fix, refactor, docs, style, test, chore, perf
3. description 用中文，不超过 50 字，描述做了什么而非怎么做的
4. 如果是多个不相关改动，用 "chore: " 开头并列举关键改动

示例:
- feat: 添加用户登录功能
- fix: 修复订单金额计算错误
- refactor: 重构支付模块逻辑
- chore: 更新依赖并优化构建配置

git diff --stat:
PROMPT_EOF
)
    prompt+=$'\n'"$DIFF_STAT"$'\n\n'
    prompt+="git diff (前 $MAX_DIFF_LINES 行):"$'\n'"$DIFF_CONTENT"

    # 调用 claude CLI
    if command -v claude &> /dev/null; then
        echo -e "${BLUE}🤖 AI 分析中...${NC}"
        claude -p "$prompt" --max-tokens 100 2>/dev/null || echo "chore: update files"
    else
        # 降级到简单模式
        generate_simple_msg "$extra"
        return
    fi
}

# 简单模式（无 AI 时降级）
generate_simple_msg() {
    local extra="$1"
    local added=$(git diff --cached --numstat | awk '{sum+=$1} END {print sum+0}')
    local deleted=$(git diff --cached --numstat | awk '{sum+=$2} END {print sum+0}')
    local files_changed=$(git diff --cached --name-only | wc -l | tr -d ' ')

    if [[ $files_changed -eq 1 ]]; then
        local single_file=$(git diff --cached --name-only | head -1)
        echo "chore: update $single_file [+${added}/-${deleted}]"
    else
        echo "chore: update $files_changed files [+${added}/-${deleted}]"
    fi
}

# 生成 commit 信息
COMMIT_MSG=$(generate_ai_commit_msg "$1")

# 如果用户提供了额外描述，添加到前面
if [[ -n "$1" ]]; then
    # 提取 type 和 description
    TYPE=$(echo "$COMMIT_MSG" | cut -d: -f1)
    DESC=$(echo "$COMMIT_MSG" | cut -d: -f2- | sed 's/^ *//')
    COMMIT_MSG="$TYPE: $1 - $DESC"
fi

echo -e "${YELLOW}📝 Commit: ${NC}$COMMIT_MSG"
echo ""

# 确认
read -p "确认提交并推送? [Y/n/e=编辑] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${RED}已取消${NC}"
    git reset HEAD
    exit 0
elif [[ $REPLY =~ ^[Ee]$ ]]; then
    # 编辑模式
    echo "请输入新的 commit 信息 (Ctrl+D 保存):"
    COMMIT_MSG=$(cat)
fi

git commit -m "$COMMIT_MSG"
git push
echo -e "${GREEN}✓ 已推送到远程${NC}"
