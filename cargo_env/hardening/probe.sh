#!/usr/bin/env bash
set -euo pipefail
# env_wrapper has initialized runfiles and sourced the environment already.
RUNFILES_DIR="${FIXTURE_ROOT%/*}"
expected_literal="cost \$5, \"double quotes\", and 'single quotes'"
[[ "$QUOTED_LITERAL" == "$expected_literal" ]]
missing=0
for name in file.h file.hpp file.hh file.hxx file.inc file.modulemap file.json extensionless plugin.so with_spaces.inc; do
 path="$FIXTURE_ROOT/cargo_env/hardening/data/$name"
 expected="fixture:$name"
 [[ "$name" != file.json ]] || expected=\"$expected\"
 if [[ -r "$path" ]] && [[ "$(cat "$path")" == "$expected" ]];then
  printf 'PASS source %s\n' "$name"
 else
  printf 'FAIL missing source %s\n' "$name"
  missing=1
 fi
done
for item in hidden.asset linked.asset; do
 if [[ "$item" == hidden.asset ]];then path="$RUNTIME_ROOT/cargo_env/hardening/$item";else path="$RUNFILES_DIR/fsw64354_runtime_only_link";fi
 if [[ -r "$path" ]] && [[ "$(cat "$path")" == "fixture:$item" ]];then printf 'PASS runfiles %s\n' "$item";else printf 'FAIL runfiles %s\n' "$item";missing=1;fi
done
if [[ -r "$RUNFILES_DIR/fsw64354 runtime link" ]] && [[ "$(cat "$RUNFILES_DIR/fsw64354 runtime link")" == 'fixture:linked.asset' ]];then printf 'PASS runfiles path with spaces\n';else printf 'FAIL runfiles path with spaces\n';missing=1;fi
generated="$FIXTURE_ROOT/cargo_env/hardening/generated.txt"
tree="$FIXTURE_ROOT/cargo_env/hardening/tree"
if [[ -r "$generated" ]] && [[ "$(cat "$generated")" == 'generated fixture' ]];then printf 'PASS generated file\n';else printf 'FAIL generated file\n';missing=1;fi
if [[ -r "$tree/generated.txt" ]] && [[ "$(cat "$tree/generated.txt")" == 'generated fixture' ]];then printf 'PASS generated tree\n';else printf 'FAIL generated tree\n';missing=1;fi
exit "$missing"
