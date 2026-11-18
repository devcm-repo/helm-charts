#!/bin/sh
set -eu
umask 077

seed=$1
config_dir=$2
config="$config_dir/config.yaml"
stamp="$config_dir/.bootstrap-sha256"

test -s "$seed"
pending=$(mktemp "$config_dir/.config.XXXXXX")
trap 'rm -f "$pending" "$pending.sha256"' EXIT

cat "$seed" > "$pending"
sha256sum < "$pending" > "$pending.sha256"
if [ -s "$config" ] && cmp -s "$pending.sha256" "$stamp"; then
    exit 0
fi

mv -f "$pending" "$config"
mv -f "$pending.sha256" "$stamp"
