#!/usr/bin/env python3
"""Embed capture images as a BLOB column into an EDTA-OCR database.

Usage:
    python3 embed_images.py /path/to/edta_ocr.db /path/to/captures/ --out edta_ocr_with_images.db
"""

import argparse
import os
import sqlite3
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Embed PNG capture images into a new database as a BLOB column.")
    parser.add_argument("db", help="Source database path")
    parser.add_argument("captures", help="Source captures directory")
    parser.add_argument("--out", required=True, help="Output database path")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        print(f"Error: database not found: {args.db}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(args.captures):
        print(f"Error: captures directory not found: {args.captures}", file=sys.stderr)
        sys.exit(1)

    src = sqlite3.connect(args.db)
    src.row_factory = sqlite3.Row

    # Read all records
    rows = src.execute(
        "SELECT 姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间 FROM records"
    ).fetchall()
    total = len(rows)
    print(f"Source records: {total}")

    # Build image lookup: bullet number → PNG binary
    # Also walk subdirectories (some captures have date-named subfolders).
    # _latest.png is skipped — it's a transient app file with no guaranteed
    # mapping to any specific bullet number.
    images = {}  # bullet_str → bytes
    for dirpath, _dirnames, filenames in os.walk(args.captures):
        for fname in filenames:
            if not fname.endswith(".png"):
                continue
            bullet = fname.replace(".png", "")
            if bullet == "_latest":
                continue
            fpath = os.path.join(dirpath, fname)
            with open(fpath, "rb") as f:
                images[bullet] = f.read()

    print(f"Images found:   {len(images)}")

    # Create output database
    out = sqlite3.connect(args.out)
    out.execute("DROP TABLE IF EXISTS records")
    out.execute("""
        CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            姓名 TEXT, 性别 TEXT, 年龄 TEXT, 住院号 TEXT,
            子弹头编号 TEXT UNIQUE, 采血时间 TEXT,
            科室 TEXT, 床号 TEXT, 原始OCR文本 TEXT,
            录入时间 TEXT DEFAULT (datetime('now','localtime')),
            图片 BLOB
        )
    """)

    embedded = 0
    missing = 0
    for r in rows:
        bullet = (r["子弹头编号"] or "").strip()
        img_data = images.get(bullet) if bullet else None
        if img_data:
            embedded += 1
        else:
            if bullet:
                missing += 1

        out.execute(
            "INSERT INTO records (姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间, 图片) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (
                r["姓名"] or "", r["性别"] or "", r["年龄"] or "",
                r["住院号"] or "", bullet,
                r["采血时间"] or "", r["科室"] or "", r["床号"] or "",
                r["原始OCR文本"] or "", r["录入时间"] or "",
                img_data,
            ),
        )

    out.commit()

    # Report
    size_mb = os.path.getsize(args.out) / (1024 * 1024)
    print(f"Embedded:       {embedded}")
    if missing:
        print(f"Missing images: {missing}")
    print(f"Output:         {args.out} ({size_mb:.1f} MB)")
    out.close()
    src.close()
    print("Done.")


if __name__ == "__main__":
    main()
