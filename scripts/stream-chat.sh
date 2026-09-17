#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  stream-chat.sh — Terminal chat client for the Lambda SSE endpoint
#
#  Usage:
#    chmod +x stream-chat.sh
#    ./stream-chat.sh                          # uses STREAM_URL env var or prompts
#    STREAM_URL=https://... ./stream-chat.sh   # pass URL inline
#
#  Dependencies: curl, sed (both pre-installed on macOS/Linux)
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colours & formatting ──────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
BLUE='\033[0;34m'

# ── Config ────────────────────────────────────────────────────────
URL="${STREAM_URL:-}"
CONNECT_TIMEOUT=10
MAX_TIME=120       # max seconds to wait for a full response

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────

clear_line()  { printf '\r\033[K'; }
move_up()     { printf '\033[1A'; }

print_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}${CYAN}│   🌊  Lambda Streaming Chat  (SSE)       │${RESET}"
  echo -e "${BOLD}${CYAN}└─────────────────────────────────────────┘${RESET}"
  echo -e "${DIM}  Type your message and press Enter.${RESET}"
  echo -e "${DIM}  Commands: ${BOLD}/quit${RESET}${DIM} or ${BOLD}/exit${RESET}${DIM} to leave, ${BOLD}/url${RESET}${DIM} to change endpoint.${RESET}"
  echo ""
}

print_separator() {
  echo -e "${DIM}  ─────────────────────────────────────────${RESET}"
}

spinner() {
  local pid=$1
  local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}${chars:$i:1}${RESET}${DIM} connecting...${RESET}"
    i=$(( (i+1) % ${#chars} ))
    sleep 0.08
  done
  clear_line
}

# Parse SSE lines and print tokens as they arrive
stream_response() {
  local prompt="$1"
  local payload
  payload=$(printf '{"prompt":"%s"}' "$(echo "$prompt" | sed 's/"/\\"/g')")

  echo -e "\n  ${BOLD}${MAGENTA}Assistant${RESET}"
  printf "  "

  local token_count=0
  local got_done=false
  local error_msg=""

  # curl flags:
  #   -N  : disable output buffering (essential for SSE)
  #   -sS : silent but show errors
  #   --no-buffer : extra insurance against curl buffering
  while IFS= read -r line; do
    # SSE lines look like:  data: {"token":"Hello "}
    # or end signal:        data: {"done":true}
    # or error:             data: {"error":"..."}

    # Normalise: strip "data: " prefix if present, skip blank/comment lines
    local json=""
    if [[ "$line" == data:* ]]; then
      json="${line#data: }"        # SSE framed:  data: {"token":"..."}
    elif [[ "$line" == "{"* ]]; then
      json="$line"                 # bare JSON:   {"token":"..."}  (LWA strips framing)
    else
      continue                     # blank line, SSE comment, etc.
    fi

    [[ -z "$json" ]] && continue

    # Check for done signal
    if echo "$json" | grep -q '"done"'; then
      got_done=true
      break
    fi

    # Check for error
    if echo "$json" | grep -q '"error"'; then
      error_msg=$(echo "$json" | sed 's/.*"error":"\([^"]*\)".*/\1/')
      break
    fi

    # Extract token using python3 for reliable JSON parsing
    local token
    token=$(echo "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('token',''), end='')
except:
    pass
")

    if [[ -n "$token" ]]; then
      printf "%s" "$token"
      token_count=$((token_count + 1))
    fi
  done < <(
    curl \
      --no-buffer \
      -sS \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$URL" 2>&1
  )

  echo ""  # newline after the streamed response

  if [[ -n "$error_msg" ]]; then
    echo -e "\n  ${RED}Error from server: ${error_msg}${RESET}"
  elif [[ "$got_done" == false && "$token_count" -eq 0 ]]; then
    echo -e "\n  ${RED}No tokens received. Check the endpoint URL and Lambda logs.${RESET}"
  fi

  echo -e "  ${DIM}(${token_count} tokens)${RESET}\n"
}

# ─────────────────────────────────────────────────────────────────
# Startup
# ─────────────────────────────────────────────────────────────────

print_banner

# Ask for URL if not set
if [[ -z "$URL" ]]; then
  printf "  ${YELLOW}Endpoint URL${RESET} (e.g. https://abc123.execute-api.us-east-1.amazonaws.com/dev/stream): "
  read -r URL
  echo ""
fi

if [[ -z "$URL" ]]; then
  echo -e "  ${RED}No URL provided. Exiting.${RESET}"
  exit 1
fi

echo -e "  ${DIM}Connected to: ${URL}${RESET}"
print_separator

# ─────────────────────────────────────────────────────────────────
# Chat loop
# ─────────────────────────────────────────────────────────────────

while true; do
  # Print prompt
  printf "\n  ${BOLD}${GREEN}You${RESET}  "

  # Read input (handle EOF / Ctrl-D gracefully)
  if ! IFS= read -r user_input; then
    echo ""
    echo -e "\n  ${DIM}Goodbye!${RESET}\n"
    break
  fi

  # Trim leading/trailing whitespace
  user_input="${user_input#"${user_input%%[![:space:]]*}"}"
  user_input="${user_input%"${user_input##*[![:space:]]}"}"

  # Skip empty input
  [[ -z "$user_input" ]] && continue

  # Built-in commands
  case "$user_input" in
    /quit|/exit|/q)
      echo -e "\n  ${DIM}Goodbye!${RESET}\n"
      break
      ;;
    /url)
      printf "  New URL: "
      read -r URL
      echo -e "  ${DIM}Updated to: ${URL}${RESET}"
      continue
      ;;
    /clear)
      clear
      print_banner
      echo -e "  ${DIM}Connected to: ${URL}${RESET}"
      print_separator
      continue
      ;;
    /help)
      echo -e "\n  ${DIM}Commands:"
      echo -e "    /quit  /exit  — exit the chat"
      echo -e "    /url          — change the endpoint URL"
      echo -e "    /clear        — clear the screen"
      echo -e "    /help         — show this help${RESET}"
      continue
      ;;
  esac

  # Send the message and stream the response
  stream_response "$user_input"
  print_separator
done
