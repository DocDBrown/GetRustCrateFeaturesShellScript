#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/crate_feature_finder.sh"
}

start_server_batch_0() {
  code="$1"
  body="$2"
  tmpdir=$(mktemp -d)
  server_py="$tmpdir/server.py"
  cat > "$server_py" <<'PY'
import sys,http.server,socketserver
CODE=int(sys.argv[1])
BODY=sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(CODE)
        self.send_header("Content-Type","text/plain")
        self.end_headers()
        self.wfile.write(BODY.encode())
    def log_message(self, format, *args):
        return
with socketserver.TCPServer(("127.0.0.1",0), Handler) as httpd:
    print(httpd.server_address[1])
    sys.stdout.flush()
    httpd.serve_forever()
PY
  python3 "$server_py" "$code" "$body" >"$tmpdir/port" 2>"$tmpdir/err" &
  server_pid=$!
  for i in $(seq 1 50); do
    if [[ -s "$tmpdir/port" ]]; then break; fi
    sleep 0.01
  done
  port=$(cat "$tmpdir/port")
  echo "$port:$server_pid:$tmpdir"
}

@test "fetch_json_returns_body_and_status_0_for_200_response" {
  result=$(start_server_batch_0 200 '{"ok":true}')
  IFS=: read port server_pid tmpdir <<< "$result"
  url="http://127.0.0.1:${port}/"
  run bash -c "source \"$SCRIPT\" && fetch_json \"$url\""
  [ "$status" -eq 0 ]
  [ "$output" = '{"ok":true}' ]
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}

@test "fetch_json_returns_empty_string_and_status_0_for_404_response" {
  result=$(start_server_batch_0 404 'Not Found')
  IFS=: read port server_pid tmpdir <<< "$result"
  url="http://127.0.0.1:${port}/"
  run bash -c "source \"$SCRIPT\" && fetch_json \"$url\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}

@test "fetch_json_prints_curl_error_and_returns_1_on_network_failure" {
  run bash -c "source \"$SCRIPT\" && fetch_json 'http://127.0.0.1:9/'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: curl command failed for http://127.0.0.1:9/"* ]]
}

@test "fetch_json_prints_http_error_and_returns_1_for_500_response" {
  result=$(start_server_batch_0 500 'Internal Server Error')
  IFS=: read port server_pid tmpdir <<< "$result"
  url="http://127.0.0.1:${port}/"
  run bash -c "source \"$SCRIPT\" && fetch_json \"$url\""
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP Status: 500"* ]]
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}

@test "fetch_json_truncates_error_body_to_100_chars_for_non_2xx_non_404_response" {
  long_body=$(printf 'A%.0s' $(seq 1 150))
  result=$(start_server_batch_0 500 "$long_body")
  IFS=: read port server_pid tmpdir <<< "$result"
  url="http://127.0.0.1:${port}/"
  expected_prefix=$(printf 'A%.0s' $(seq 1 100))
  run bash -c "source \"$SCRIPT\" && fetch_json \"$url\""
  [ "$status" -eq 1 ]
  [[ "$output" == *"${expected_prefix}..."* ]]
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}
