#!/usr/bin/env bats

setup() {
  TMPDIR=$(mktemp -d)
}

teardown() {
  if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
    rm -rf "$TMPDIR"
  fi
}

write_mock_curl_batch_1() {
  cat > "$TMPDIR/curl" <<'MOCK'
#!/bin/bash
if [[ "$MOCK_CURL_BEHAVIOR" == "success" ]]; then
  printf 'MOCKBODY\n200'
  exit 0
elif [[ "$MOCK_CURL_BEHAVIOR" == "fail" ]]; then
  exit 7
else
  printf 'ERRORBODY\n500'
  exit 0
fi
MOCK
  chmod +x "$TMPDIR/curl"
}

@test "fetch_json_sleeps_after_successful_api_call" {
  write_mock_curl_batch_1
  PATH="$TMPDIR:$PATH"
  export MOCK_CURL_BEHAVIOR=success
  SCRIPT="${BATS_TEST_DIRNAME}/crate_feature_finder.sh"
  start_ns=$(date +%s%N)
  run bash -c "source \"$SCRIPT\" >/dev/null 2>&1; fetch_json 'http://example' >/dev/null 2>&1"
  status=$status
  end_ns=$(date +%s%N)
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  [ "$status" -eq 0 ]
  if [ "$elapsed_ms" -lt 150 ]; then
    echo "fetch_json did not sleep long enough: ${elapsed_ms}ms" >&2
    false
  fi
}

@test "fetch_json_does_not_sleep_on_error_exit" {
  write_mock_curl_batch_1
  PATH="$TMPDIR:$PATH"
  export MOCK_CURL_BEHAVIOR=fail
  SCRIPT="${BATS_TEST_DIRNAME}/crate_feature_finder.sh"
  start_ns=$(date +%s%N)
  run bash -c "source \"$SCRIPT\" >/dev/null 2>&1; fetch_json 'http://example' >/dev/null 2>&1"
  status=$status
  end_ns=$(date +%s%N)
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  [ "$status" -ne 0 ]
  if [ "$elapsed_ms" -ge 100 ]; then
    echo "fetch_json slept on error path: ${elapsed_ms}ms" >&2
    false
  fi
}
