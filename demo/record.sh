#!/bin/sh
# Drives the README demo against a throwaway repository, so a recording shows
# a believable crate rather than an empty one.
#
#   asciinema rec demo.cast -c 'demo/record.sh'
#
# Set SELECTA_AO=null to rehearse silently.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
DEMO=${TMPDIR:-/tmp}/selecta-demo
SELECTA_HOME=$DEMO/home
export SELECTA_HOME

rm -rf "$DEMO"
mkdir -p "$DEMO/demo-api"
cd "$DEMO/demo-api"
git init -q -b main
git config user.name "Azanda"
git config user.email "azandagp@gmail.com"
git commit -q --allow-empty -m "initial commit"
git commit -q --allow-empty -m "add session cookie rotation"
git commit -q --allow-empty -m "fix auth redirect loop"
git remote add origin git@github.com:azandabot/demo-api.git

S=$ROOT/bin/selecta

say() { printf '\n\033[2m$\033[0m %s\n' "$*"; }
pause() { sleep "${1:-2}"; }

say "selecta play amapiano"
pause 1
$S play amapiano
pause 8

say "selecta"
pause 1
$S
pause 4

say "selecta vol 45"
pause 1
$S vol 45
pause 2

say "selecta play something calm for reading"
pause 1
$S play something calm for reading
pause 8

say "selecta crate"
pause 1
$S crate
pause 6

say "selecta resume"
pause 1
$S resume
pause 4

say "selecta stop"
pause 1
$S stop

printf '\n\033[2mDemo repo left at %s\033[0m\n' "$DEMO"
