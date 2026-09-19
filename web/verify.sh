#!/bin/bash
# Checks the live site answers agents the way it claims to. Usage: ./verify.sh [origin]
ORIGIN="${1:-https://getblackhole.app}"
pass=0; fail=0
check() { # name, expected, actual
  if [ "$3" = "$2" ]; then printf "  ok   %s\n" "$1"; pass=$((pass+1));
  else printf "  FAIL %s — wanted '%s', got '%s'\n" "$1" "$2" "$3"; fail=$((fail+1)); fi
}
contains() {
  if printf '%s' "$3" | grep -qi -- "$2"; then printf "  ok   %s\n" "$1"; pass=$((pass+1));
  else printf "  FAIL %s — '%s' not found\n" "$1" "$2"; fail=$((fail+1)); fi
}

echo "Markdown negotiation on the homepage"
h=$(curl -sS -L -D- -o/dev/null -H 'Accept: text/markdown' "$ORIGIN/")
contains "content-type is markdown" "content-type: text/markdown" "$h"
contains "varies on Accept" "vary: accept" "$h"
body=$(curl -sS -L -H 'Accept: text/markdown' "$ORIGIN/")
contains "body is the markdown homepage" "# Black Hole" "$body"

echo "HTML is untouched"
h=$(curl -sS -L -D- -o/dev/null -H 'Accept: text/html' "$ORIGIN/")
contains "content-type is html" "content-type: text/html" "$h"

echo "404s"
code=$(curl -sS -L -o/dev/null -w '%{http_code}' "$ORIGIN/__does-not-exist")
check "html 404 status" "404" "$code"
code=$(curl -sS -L -o/dev/null -w '%{http_code}' -H 'Accept: text/markdown' "$ORIGIN/__does-not-exist")
check "markdown 404 status" "404" "$code"
h=$(curl -sS -L -D- -o/dev/null -H 'Accept: text/markdown' "$ORIGIN/__does-not-exist")
contains "markdown 404 content-type" "content-type: text/markdown" "$h"
body=$(curl -sS -L -H 'Accept: text/markdown' "$ORIGIN/__does-not-exist")
contains "markdown 404 explains itself" "page not found" "$body"
contains "markdown 404 links onward" "llms.txt" "$body"

echo "Machine-readable files"
for path in /llms.txt /sitemap.xml /robots.txt /.well-known/mcp; do
  code=$(curl -sS -L -o/dev/null -w '%{http_code}' "$ORIGIN$path")
  check "$path" "200" "$code"
done
contains "llms.txt says when to use it" "when to use this" "$(curl -sS -L "$ORIGIN/llms.txt")"

echo "Trust pages"
for path in /about /contact /privacy; do
  code=$(curl -sS -L -o/dev/null -w '%{http_code}' "$ORIGIN$path")
  check "$path" "200" "$code"
  md=$(curl -sS -L -H 'Accept: text/markdown' "$ORIGIN$path")
  contains "$path as markdown" "##" "$md"
done

echo "Metadata"
home=$(curl -sS -L "$ORIGIN/")
contains "canonical" 'rel="canonical"' "$home"
contains "og:type" 'property="og:type"' "$home"
contains "og:image" 'property="og:image"' "$home"
contains "html lang" '<html lang=' "$home"
contains "Organization schema" '"@type":"Organization"' "$home"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
