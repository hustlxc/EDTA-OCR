#!/usr/bin/env python3
"""Merge multiple EDTA-OCR databases WITH embedded image BLOBs into one.

Usage:
    # Merge all DB files in a directory:
    python3 merge_embedded_db.py merged_db/ --out merged_embedded.db

    # Dry run — report conflicts only:
    python3 merge_embedded_db.py merged_db/

    # Force merge with options:
    python3 merge_embedded_db.py merged_db/ --force --out merged.db
    python3 merge_embedded_db.py merged_db/ --force --keep-duplicates --out merged.db
"""

import argparse
import os
import sqlite3
import sys
from collections import OrderedDict


def load_db(db_path):
    """Load all records (including BLOB) from a database. Returns list of dicts."""
    if not os.path.exists(db_path):
        print(f"  [SKIP] {db_path}: not found")
        return []
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT 姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间, 图片 FROM records"
    ).fetchall()
    conn.close()
    records = []
    for r in rows:
        records.append({
            "name": r[0] or "", "gender": r[1] or "", "age": r[2] or "",
            "serial": r[3] or "", "bullet": r[4] or "", "time": r[5] or "",
            "dept": r[6] or "", "bed": r[7] or "", "ocr": r[8] or "",
            "saved": r[9] or "", "image": r[10],
            "source_db": db_path,
        })
    return records


def main():
    parser = argparse.ArgumentParser(
        description="Merge EDTA-OCR databases with embedded image BLOBs",
        epilog="Each .db file in the input directory is treated as a source.")
    parser.add_argument("input_dir",
                        help="Directory containing .db files to merge")
    parser.add_argument("--force", action="store_true",
                        help="Actually perform the merge (without this, only report conflicts)")
    parser.add_argument("--keep-duplicates", action="store_true",
                        help="Keep all records even when bullet numbers conflict")
    parser.add_argument("--out", default="merged_embedded.db",
                        help="Output merged database")
    args = parser.parse_args()

    if not os.path.isdir(args.input_dir):
        print(f"Error: directory not found: {args.input_dir}", file=sys.stderr)
        sys.exit(1)

    # Find all .db files
    db_files = sorted(
        os.path.join(args.input_dir, f)
        for f in os.listdir(args.input_dir)
        if f.endswith(".db") or f.endswith(".sqlite") or f.endswith(".sqlite3")
    )
    if not db_files:
        # Some files may have no extension (as shown in the listing)
        db_files = sorted(
            os.path.join(args.input_dir, f)
            for f in os.listdir(args.input_dir)
            if os.path.isfile(os.path.join(args.input_dir, f))
            and not f.startswith(".")
        )
        # Filter: try opening as sqlite
        verified = []
        for path in db_files:
            try:
                conn = sqlite3.connect(path)
                conn.execute("SELECT 1 FROM records LIMIT 1")
                conn.close()
                verified.append(path)
            except Exception:
                pass
        db_files = verified

    if not db_files:
        print("Error: no valid database files found", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(db_files)} database files in {args.input_dir}/")

    # Load all databases
    print("\nLoading databases...")
    all_sources = []
    for db_path in db_files:
        records = load_db(db_path)
        if records:
            all_sources.append((db_path, records))
            label = os.path.basename(db_path)
            total_mb = sum(len(r.get("image") or b"") for r in records) / (1024 * 1024)
            print(f"  {label}: {len(records)} records, {total_mb:.1f} MB of images")

    # Find conflicts
    print("\nChecking for conflicts...")
    seen = OrderedDict()
    for db_path, records in all_sources:
        for rec in records:
            b = rec["bullet"]
            if not b:
                continue
            if b not in seen:
                seen[b] = []
            seen[b].append((db_path, rec))

    conflicts = {b: entries for b, entries in seen.items() if len(entries) > 1}
    singletons = {b: entries[0] for b, entries in seen.items() if len(entries) == 1}

    if conflicts:
        print(f"\n  {len(conflicts)} bullet numbers appear in multiple databases:")
        for b, entries in conflicts.items():
            print(f"\n  Bullet {b}:")
            for db_path, rec in entries:
                db_label = os.path.basename(db_path)
                print(f"    {db_label}: 姓名={rec['name']} 住院号={rec['serial']} 录入={rec['saved']}")
    else:
        print("  No conflicts found.")

    conflict_records = sum(len(v) for v in conflicts.values())
    print(f"\nSummary: {len(singletons)} unique, {len(conflicts)} conflicting bullets ({conflict_records} records)")

    if not args.force:
        if conflicts:
            if args.keep_duplicates:
                print("\nRun with --force --keep-duplicates to keep all conflicting records.")
            else:
                print("\nRun with --force to merge (last file wins on conflict).")
                print("         --keep-duplicates to keep all conflicting records instead.")
        else:
            print("\nNo conflicts. Run with --force to proceed with merge.")
        return

    # --- Merge ---
    print("\nMerging...")
    unique_clause = "" if args.keep_duplicates else "UNIQUE"
    out = sqlite3.connect(args.out)
    out.execute("DROP TABLE IF EXISTS records")
    out.execute(f"""
        CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            姓名 TEXT, 性别 TEXT, 年龄 TEXT, 住院号 TEXT,
            子弹头编号 TEXT {unique_clause}, 采血时间 TEXT,
            科室 TEXT, 床号 TEXT, 原始OCR文本 TEXT,
            录入时间 TEXT DEFAULT (datetime('now','localtime')),
            图片 BLOB
        )
    """)

    merged = 0

    # Insert singletons
    for b, (db_path, rec) in singletons.items():
        out.execute("DELETE FROM records WHERE 子弹头编号 = ?", (b,))
        out.execute(
            "INSERT INTO records (姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间, 图片) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (rec["name"], rec["gender"], rec["age"], rec["serial"], b,
             rec["time"], rec["dept"], rec["bed"], rec["ocr"], rec["saved"],
             rec["image"]),
        )
        merged += 1

    # Insert conflicts
    if args.keep_duplicates:
        for b, entries in conflicts.items():
            for _db_path, rec in entries:
                out.execute(
                    "INSERT INTO records (姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间, 图片) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (rec["name"], rec["gender"], rec["age"], rec["serial"], b,
                     rec["time"], rec["dept"], rec["bed"], rec["ocr"], rec["saved"],
                     rec["image"]),
                )
                merged += 1
    else:
        for b, entries in conflicts.items():
            _, winner = entries[-1]
            out.execute("DELETE FROM records WHERE 子弹头编号 = ?", (b,))
            out.execute(
                "INSERT INTO records (姓名, 性别, 年龄, 住院号, 子弹头编号, 采血时间, 科室, 床号, 原始OCR文本, 录入时间, 图片) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (winner["name"], winner["gender"], winner["age"], winner["serial"], b,
                 winner["time"], winner["dept"], winner["bed"], winner["ocr"], winner["saved"],
                 winner["image"]),
            )
            merged += 1

    out.commit()
    out.close()

    size_mb = os.path.getsize(args.out) / (1024 * 1024)
    print(f"  {merged} records written to {args.out} ({size_mb:.1f} MB)")
    print("Done.")


if __name__ == "__main__":
    main()
