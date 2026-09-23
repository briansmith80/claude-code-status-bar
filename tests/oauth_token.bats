#!/usr/bin/env bats
#
# OAuth usage fetch — which token gets sent:
#   - the Keychain item / credentials file holding Claude Code's login
#     (claudeAiOauth) also stores OAuth tokens for MCP servers (mcpOAuth),
#     and those can come first in the document
#   - the fetch must send the claudeAiOauth token, not the first accessToken
#   - layouts without a claudeAiOauth entry keep the first-match behaviour
#
# curl and security are stubbed on PATH, so no real Keychain or network is
# touched; the credentials come from the sandbox's .credentials.json.

load test_helper

# Put stub curl/security first on PATH. The curl stub records the bearer token
# it was handed via `--config -` (stdin) and answers with a minimal payload.
make_stubs() {
  STUB_BIN="${TEST_HOME}/bin"
  AUTH_LOG="${TEST_HOME}/auth-seen"
  mkdir -p "$STUB_BIN"
  printf '%s\n' '#!/bin/sh' 'exit 1' > "${STUB_BIN}/security"
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/sh
grep -o 'Bearer [^"]*' > "$AUTH_LOG"
printf '%s' '{"five_hour":{"utilization":10.0,"resets_at":null},"seven_day":{"utilization":5.0,"resets_at":null}}'
EOF
  chmod +x "${STUB_BIN}/security" "${STUB_BIN}/curl"
}

# stdin without rate_limits, so the 5h/7d numbers need the OAuth fetch
NO_RATE_LIMITS_JSON='{"cwd":"/tmp","model":{"display_name":"Opus"},"context_window":{"used_percentage":40}}'

# Render once and wait for the detached fetch to record the token it sent.
fetch_and_wait() {
  run_statusline_env "$NO_RATE_LIMITS_JSON" "PATH=${STUB_BIN}:${PATH}" "AUTH_LOG=${AUTH_LOG}"
  local i
  for i in $(seq 1 25); do
    [ -s "$AUTH_LOG" ] && return 0
    sleep 0.2
  done
  return 1
}

@test "claudeAiOauth token is sent even when MCP OAuth entries come first" {
  make_stubs
  cat > "${TEST_HOME}/.claude/.credentials.json" <<'EOF'
{"mcpOAuth":{"plugin:stripe:stripe|b6f5a41be97b6eed":{"serverName":"plugin:stripe:stripe","serverUrl":"https://mcp.stripe.com","accessToken":"mcp-token","expiresAt":1754984237000}},"claudeAiOauth":{"accessToken":"login-token","refreshToken":"r","expiresAt":1790395336000,"scopes":["user:inference","user:profile"],"subscriptionType":"team"}}
EOF
  fetch_and_wait
  [ "$(cat "$AUTH_LOG")" = "Bearer login-token" ]
}

@test "a credentials file without claudeAiOauth still uses its accessToken" {
  make_stubs
  printf '%s' '{"accessToken":"legacy-token","expiresAt":1790395336000}' \
    > "${TEST_HOME}/.claude/.credentials.json"
  fetch_and_wait
  [ "$(cat "$AUTH_LOG")" = "Bearer legacy-token" ]
}
