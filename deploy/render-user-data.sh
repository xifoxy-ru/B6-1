#!/bin/bash
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
[ "$#" = 2 ] && [ "$1" = --output ] || { printf 'usage: render-user-data.sh --output runtime/file.sh\n' >&2; exit 1; }
out=$2
case "$out" in /*) ;; *) out="$ROOT/$out";; esac
case "$out" in "$ROOT/runtime/"*) ;; *) exit 1;; esac
case "$out" in */../*|*/./*) exit 1;; esac
p=$out; while [ "$p" != / ]; do [ ! -L "$p" ] || exit 1; p=$(dirname -- "$p"); done
[ ! -e "$out" ] || { printf 'output exists; no overwrite\n' >&2; exit 1; }
mkdir -p "$(dirname -- "$out")"
index=$(base64 < "$ROOT/app/index.html" | tr -d '\n')
nginx=$(base64 < "$ROOT/deploy/nginx.conf" | tr -d '\n')
compose=$(base64 < "$ROOT/deploy/compose.yaml" | tr -d '\n')
(umask 077; set -C; sed -e "s|@@INDEX_B64@@|$index|g" -e "s|@@NGINX_B64@@|$nginx|g" -e "s|@@COMPOSE_B64@@|$compose|g" "$ROOT/deploy/user-data.sh.tpl" > "$out")
[ "$(wc -c < "$out" | tr -d ' ')" -le 16384 ]
! grep -q '@@' "$out"
bash -n "$out"
