#!/usr/bin/env bash
# Brings a lesson manifest's [[references]] up to date with the links in its Markdown: linked pages first, in
# the order they appear, then any reference the manifest already had that the text does not link (never dropped:
# remove a dead one by hand). Titles already in the manifest are kept; others come from "url<TAB>title" lines
# on stdin, or else the last part of the link.
#   bash tools/lesson-refs.sh course/area/name < titles.tsv
# It does not check that links load.
set -e
base=$1
md=$base.md
toml=$base.toml
tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.titles" "$tmp.urls"' EXIT
tr -d '\r' < "$toml" | awk '/^\[\[references\]\]/{on=1} on && /^title = /{t=$0; sub(/^title = "/,"",t); sub(/"$/,"",t)} on && /^url = /{u=$0; sub(/^url = "/,"",u); sub(/"$/,"",u); print u "\t" t}' > "$tmp.titles"
cut -f1 "$tmp.titles" > "$tmp.urls"          # what the manifest had, before anything is added
if [ ! -t 0 ]; then tr -d '\r' >> "$tmp.titles"; fi
awk '/^\[\[references\]\]/{exit} {print}' "$toml" > "$tmp"
{ grep -oE 'https://[^) >]+' "$md" || true; cat "$tmp.urls"; } | awk 'NF && !seen[$0]++' | while read -r url; do
    title=$(awk -F '\t' -v u="$url" '$1 == u {t=$2} END {print t}' "$tmp.titles")
    [ -n "$title" ] || title=${url##*/}
    printf '[[references]]\ntitle = "%s"\nurl = "%s"\n\n' "$title" "$url" >> "$tmp"
done
cat "$tmp" > "$toml"
echo "$(grep -c '^url = ' "$toml") references in $toml"
