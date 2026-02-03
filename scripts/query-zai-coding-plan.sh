#!/bin/bash
# Query Z.AI Coding Plan usage via OpenCode auth
# Token: ~/.local/share/opencode/auth.json (key: zai-coding-plan)
# API Endpoints:
#   - Quota: https://api.z.ai/api/monitor/usage/quota/limit
#   - Model usage: https://api.z.ai/api/monitor/usage/model-usage
#   - Tool usage: https://api.z.ai/api/monitor/usage/tool-usage

set -e

AUTH_FILE="$HOME/.local/share/opencode/auth.json"

if [[ ! -f "$AUTH_FILE" ]]; then
    echo "Error: OpenCode auth file not found at $AUTH_FILE"
    exit 1
fi

# Z.AI Coding Plan uses API key directly (not OAuth)
API_KEY=$(jq -r '.["zai-coding-plan"].key // empty' "$AUTH_FILE")

if [[ -z "$API_KEY" ]]; then
    echo "Error: No Z.AI Coding Plan API key found in auth file"
    echo "Expected key: zai-coding-plan"
    exit 1
fi

echo "=== Z.AI Coding Plan Usage ==="
echo ""

# Fetch quota limits
echo "--- Quota Limits ---"
QUOTA_RESPONSE=$(curl -s "https://api.z.ai/api/monitor/usage/quota/limit" \
    -H "Authorization: $API_KEY" \
    -H "Accept-Language: en-US,en" \
    -H "Content-Type: application/json")

if echo "$QUOTA_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: $(echo "$QUOTA_RESPONSE" | jq -r '.error.message // .error')"
    exit 1
fi

# Parse and display quota information
echo "$QUOTA_RESPONSE" | jq '
if .data then
    .data
else
    .
end
| if .limits then
    .limits | map({
        type: .type,
        percentage: ((.percentage // (if .currentValue != null and .total != null and .total > 0 then (.currentValue / .total * 100) else null end)) | if . then "\(. | floor)%" else "N/A" end),
        current: .currentValue,
        total: .total,
        reset_time: (if .nextResetTime then (.nextResetTime / 1000 | strftime("%Y-%m-%d %H:%M:%S UTC")) else null end)
    })
else
    .
end'

echo ""
echo "--- Model Usage (Last 24h) ---"

# Calculate time range for last 24 hours (API expects yyyy-MM-dd HH:mm:ss format)
END_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
START_TIME=$(date -u -v-24H +"%Y-%m-%d %H:%M:%S")

MODEL_RESPONSE=$(curl -s "https://api.z.ai/api/monitor/usage/model-usage" \
    -G --data-urlencode "startTime=$START_TIME" --data-urlencode "endTime=$END_TIME" \
    -H "Authorization: $API_KEY" \
    -H "Accept-Language: en-US,en" \
    -H "Content-Type: application/json")

echo "$MODEL_RESPONSE" | jq '
if .data then
    .data
else
    .
end
| if .totalUsage then
    {
        total_tokens: .totalUsage.totalTokensUsage,
        total_calls: .totalUsage.totalModelCallCount
    }
else
    .
end'

echo ""
echo "--- Tool Usage (Last 24h) ---"

TOOL_RESPONSE=$(curl -s "https://api.z.ai/api/monitor/usage/tool-usage" \
    -G --data-urlencode "startTime=$START_TIME" --data-urlencode "endTime=$END_TIME" \
    -H "Authorization: $API_KEY" \
    -H "Accept-Language: en-US,en" \
    -H "Content-Type: application/json")

echo "$TOOL_RESPONSE" | jq '
if .data then
    .data
else
    .
end
| if .totalUsage then
    {
        network_search: .totalUsage.totalNetworkSearchCount,
        web_read_mcp: .totalUsage.totalWebReadMcpCount,
        zread_mcp: .totalUsage.totalZreadMcpCount
    }
else
    .
end'
