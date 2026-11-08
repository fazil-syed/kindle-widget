#!/bin/zsh
# widget-data.sh — produces the JSON the Übersicht widget renders.
# Self-locating: lives next to the kindle-progress binary.

KW_DIR="${0:A:h}"
CACHE_DIR="$HOME/Library/Application Support/KindleWidget"

raw=$("$KW_DIR/kindle-progress" --json 2>/dev/null) || { echo '{"pos":null,"books":[]}'; exit 0; }

count=$(printf '%s' "$raw" | jq '[.[]] | length' 2>/dev/null)
[ "$count" = "0" ] && { echo '{"pos":null,"books":[]}'; exit 0; }

pos="null"
if [ -s "$CACHE_DIR/position.json" ]; then
  pos=$(jq -c '{x: .x, y: .y}' "$CACHE_DIR/position.json" 2>/dev/null)
fi

printf '%s' "$raw" | jq -c '.[]' | while IFS= read -r book; do
  book_id=$(printf '%s' "$book" | jq -r '.bookId' | tr -cd 'A-Za-z0-9')
  cur=$(printf '%s' "$book" | jq '.currentLocation')
  max=$(printf '%s' "$book" | jq '.maxLocation')
  title=$(printf '%s' "$book" | jq -r '.title')
  author=$(printf '%s' "$book" | jq -r '.author')
  cache="$CACHE_DIR/pages-${book_id}.json"

  pages=""; source=""

  if [ -s "$cache" ]; then
    pages=$(jq -r '.printPages // empty' "$cache" 2>/dev/null)
    if [ -n "$pages" ]; then
      source=$(jq -r '.source // "cache"' "$cache" 2>/dev/null)
    fi
  fi

  if [ -z "$pages" ]; then
    # Local PDF via Spotlight
    cand=$(mdfind -name "$title" 2>/dev/null | grep -i '\.pdf$' | head -1)
    if [ -n "$cand" ]; then
      pdf_pages=$(mdls -name kMDItemNumberOfPages -raw "$cand" 2>/dev/null)
      case "$pdf_pages" in (*[0-9]*) ;;
        *) pdf_pages="" ;;
      esac
      if [ -n "$pdf_pages" ] && [ "$pdf_pages" -gt 0 ] 2>/dev/null; then
        pages="$pdf_pages"; source="local-pdf"
      fi
    fi
    # Open Library fallback, cached (works offline afterwards)
    if [ -z "$pages" ] && /usr/bin/curl -s -m 3 -o /dev/null https://openlibrary.org 2>/dev/null; then
      query=$(printf '%s' "$title $author" | /usr/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read(120)))' 2>/dev/null)
      ol=$(/usr/bin/curl -s -m 6 "https://openlibrary.org/search.json?q=${query}&fields=number_of_pages_median&limit=5" 2>/dev/null)
      ol_pages=$(printf '%s' "$ol" | jq -r '[.docs[] | .number_of_pages_median // empty][0] // empty' 2>/dev/null)
      if [ -n "$ol_pages" ] && [ "$ol_pages" != "null" ]; then
        pages="$ol_pages"; source="openlibrary"
      fi
    fi
    printf '{"printPages":%s,"source":"%s","fetchedAt":%s}\n' \
      "${pages:-null}" "${source:-failed}" "$(date +%s)" > "$cache"
  fi

  page=""
  if [ -n "$pages" ] && [ "$pages" -gt 0 ] 2>/dev/null; then
    page=$(/usr/bin/python3 -c "print(max(1, round(float(${cur}) * ${pages} / float(${max}))))" 2>/dev/null)
  fi

  printf '%s' "$book" | jq --argjson pages "${pages:-null}" --argjson p "${page:-null}" --arg src "${source:-none}" \
    '{title, author, bookId, percent} + {printPages: $pages, currentPage: $p, pageSource: $src}'
done | jq -s --argjson pos "$pos" '{pos: $pos, books: .}'
