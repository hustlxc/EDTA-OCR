#!/bin/bash
set -e

mkdir -p merged_db

while read -r db captures; do
    e=$(dirname "$db")
    out_db="merged_db/$(basename "$e").db"
    if [ ! -e "$out_db" ]; then
        python3 embed_images.py "$db" "$captures" --out "$out_db"
    fi
done < paths.txt

python3 merge_embedded_db.py merged_db/ --force --keep-duplicates --out merged_embedded.db

