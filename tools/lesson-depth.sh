#!/usr/bin/env bash
# A rough guide to which lessons to deepen first (docs/depth-review.md). It counts, per lesson:
#   words    words outside code blocks
#   blocks   fenced code blocks
#   w/block  prose words per code block (low = commands with little said about them)
#   bare     blocks followed straight away by a heading, another block or the end: nothing explains the output
#   tables   table headers, often "how to read this"
# It cannot judge whether an explanation is good. Run from the repository root:  bash tools/lesson-depth.sh
printf '%s\t%s\t%s\t%s\t%s\t%s\n' words blocks w/block bare tables lesson
for f in course/*/*.md; do
    awk -v name="$f" '
        { sub(/\r$/, "") }
        /^[ \t]*```/ { if (inside) { inside = 0; after = 1 } else { if (after) bare++; inside = 1; blocks++; after = 0 }; next }
        inside { next }
        /^[ \t]*$/ { next }
        after { if ($0 ~ /^#/) bare++; after = 0 }
        /^\|[ \t]*:?-+/ { tables++ }
        { words += NF }
        END { if (after) bare++
              printf "%d\t%d\t%d\t%d\t%d\t%s\n", words, blocks, (blocks ? words / blocks : words), bare, tables, name }
    ' "$f"
done | sort -t "$(printf '\t')" -k1,1n
