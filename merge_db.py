#!/usr/bin/env python3
"""Merge multiple EDTA-OCR databases and captures/ directories into one.

Usage:
    python3 merge_db.py --db db1.db --captures captures1/ --db db2.db --captures captures2/ --out merged.db --out-captures merged_captures/

Each --db must be followed by its corresponding --captures directory.
The output DB is created fresh. Duplicates (same bullet number) keep the
LAST record encountered. All capture images are copied to the output directory.
"""

import argparse, sqlite3, os, shutil, sys

def main():
    parser = argparse.ArgumentParser(description="Merge EDTA-OCR databases")
    parser.add_argument("--db", action="append", dest="dbs", default=[], help="Input database file")
    parser.add_argument("--captures", action="append", dest="caps", default=[], help="Captures directory for preceding --db")
    parser.add_argument("--out", required=True, help="Output merged database")
    parser.add_argument("--out-captures", default="merged_captures", help="Output captures directory")
    args = parser.parse_args()

    if len(args.dbs) != len(args.caps):
        print("Error: each --db needs a matching --captures", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    os.makedirs(args.out_captures, exist_ok=True)

    out_db = sqlite3.connect(args.out)
    out_db.execute("""
        CREATE TABLE IF NOT EXISTS records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            姓名 TEXT, 性别 TEXT, 年龄 TEXT, 住院号 TEXT,
            子弹头编号 TEXT UNIQUE, 采血时间 TEXT,
            科室 TEXT, 床号 TEXT, 原始OCR文本 TEXT,
            录入时间 TEXT DEFAULT (datetime('now','localtime'))
        )
    """)

    total = 0
    for db_path, cap_dir in zip(args.dbs, args.caps):
        if not os.path.exists(db_path):
            print(f"Skip: {db_path} not found")
            continue

        src = sqlite3.connect(db_path)
        # Read all columns except id
        rows = src.execute(
            "SELECT 姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间 FROM records"
        ).fetchall()
        src.close()

        for i, row in enumerate(rows):
            name, gender, age, serial, bullet, coll_time, dept, bed, raw_ocr, saved = row
            if not bullet:
                continue
            # upsert by bullet number
            out_db.execute("DELETE FROM records WHERE 子弹头编号 = ?", (bullet,))
            out_db.execute(
                "INSERT INTO records (姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间) VALUES (?,?,?,?,?,?,?,?,?,?)",
                (name, gender, age, serial, bullet, coll_time, dept, bed, raw_ocr, saved)
            )

        # Copy images
        if os.path.isdir(cap_dir):
            copied = 0
            for fname in os.listdir(cap_dir):
                src_path = os.path.join(cap_dir, fname)
                dst_path = os.path.join(args.out_captures, fname)
                if os.path.isfile(src_path) and fname.endswith(".png"):
                    shutil.copy2(src_path, dst_path)
                    copied += 1
            print(f"  {db_path}: {len(rows)} records, {copied} images")
        else:
            print(f"  {db_path}: {len(rows)} records, captures dir not found")

        total += len(rows)

    out_db.commit()
    out_db.close()
    print(f"\nMerged: {total} rows -> {args.out}")
    print(f"Images: {args.out_captures}/")

if __name__ == "__main__":
    main()
