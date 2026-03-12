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
MAX_DIFF_LINES=300
DIFF_CONTENT=$(git diff --cached | head -n $MAX_DIFF_LINES)
DIFF_STAT=$(git diff --cached --stat)

# 调用 Claude API
call_claude_api() {
    local prompt="$1"
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)
    curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-dangerous-direct-browser-access: true" \
        -d "{
            \"model\": \"claude-sonnet-4-20250514\",
            \"max_tokens\": 100,
            \"messages\": [{\"role\": \"user\", \"content\": $escaped_prompt}]
        }" 2>/dev/null | jq -r '.content[0].text' 2>/dev/null
}

# 调用 OpenAI API
call_openai_api() {
    local prompt="$1"
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)
    curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "{
            \"model\": \"gpt-4o-mini\",
            \"max_tokens\": 100,
            \"messages\": [{\"role\": \"user\", \"content\": $escaped_prompt}]
        }" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null
}

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
5. 只输出 commit message，不要代码块或其他内容

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

    # 调用 AI API
    echo -e "${BLUE}🤖 AI 分析中...${NC}" >&2

    local result=""
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        result=$(call_claude_api "$prompt")
    elif [[ -n "$OPENAI_API_KEY" ]]; then
        result=$(call_openai_api "$prompt")
    fi

    if [[ -n "$result" ]]; then
        # 清理可能的多余输出（代码块等）
        echo "$result" | sed 's/^```.*$//g' | sed 's/```//g' | tr -d '\n' | head -c 100
    else
        generate_simple_msg "$extra"
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

echo ""
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
