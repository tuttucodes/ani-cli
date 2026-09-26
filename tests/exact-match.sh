#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/curl_firefox135" <<'EOF'
#!/bin/sh
for arg do
    case "$arg" in
        *search\?keyword=*)
            printf '%s\n' "$arg" >>"$MOCK_CURL_LOG"
            printf '%s' '<div class="film-detail"><h3 class="film-name"><a href="/wrong-show-111" title="Wrong Show">Wrong Show</a></h3></div><div class="film-detail"><h3 class="film-name"><a href="/target-show-222" title="Target Show">Target Show</a></h3></div><div class="film-detail"><h3 class="film-name"><a href="/plus-show-333" title="A+B">A+B</a></h3></div> 200'
            exit 0
            ;;
        */api/theme/episode/list/*)
            printf '%s\n' "$arg" >>"$MOCK_CURL_LOG"
            printf '%s' 'fixture ends before episode retrieval 599'
            exit 0
            ;;
    esac
done
exit 1
EOF
cat >"$test_dir/bin/mock-menu" <<'EOF'
#!/bin/sh
head -n 1
EOF
chmod +x "$test_dir/bin/curl_firefox135" "$test_dir/bin/mock-menu"

run_case() {
    match_mode=$1
    query=$2
    shift 2
    : >"$test_dir/curl.log"
    PATH="$test_dir/bin:$PATH" MOCK_CURL_LOG="$test_dir/curl.log" \
        ANI_CLI_PLAYER=debug ANI_CLI_MENU=mock-menu ANI_CLI_HIST_DIR="$test_dir/history" \
        ANI_CLI_EXACT_MATCH="$match_mode" "$repo_dir/ani-cli" "$@" "$query" \
        >"$test_dir/output" 2>&1 || :
}

run_case 1 'tArGeT sHoW' -S 1 -e 1
grep -q '/api/theme/episode/list/222' "$test_dir/curl.log"
if grep -q '/api/theme/episode/list/111' "$test_dir/curl.log"; then
    exit 1
fi

run_case 1 'Missing Show' -e 1
curl_calls=$(wc -l <"$test_dir/curl.log")
test "$curl_calls" -eq 1
grep -q 'No exact match found' "$test_dir/output"

run_case 1 'Target.*' -e 1
curl_calls=$(wc -l <"$test_dir/curl.log")
test "$curl_calls" -eq 1
grep -q 'No exact match found' "$test_dir/output"

run_case 1 'A+B' -e 1
grep -q 'search?keyword=A%2BB' "$test_dir/curl.log"
grep -q '/api/theme/episode/list/333' "$test_dir/curl.log"

run_case 0 'Missing Show' -e 1
grep -q '/api/theme/episode/list/111' "$test_dir/curl.log"

printf '%s\n' 'Exact match search tests passed'
