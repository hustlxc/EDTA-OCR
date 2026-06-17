#!/usr/bin/env python3
"""Merge multiple EDTA-OCR databases and captures/ directories into one.

Usage:
    # Prepare a paths file (one line per source):
    #   path1/edta_ocr.db path1/captures
    #   path2/edta_ocr.db path2/captures

    # Dry run — report conflicts only
    python3 merge_db.py paths.txt

    # Force merge (last entry wins on conflict)
    python3 merge_db.py paths.txt --force --out merged.db --out-captures merged_captures/

Without --force, conflicts are reported but nothing is written.
"""

import argparse, sqlite3, os, shutil, sys
from collections import OrderedDict

def load_db(db_path, cap_dir):
    """Load all records from a database. Returns list of dicts."""
    if not os.path.exists(db_path):
        print(f"  [SKIP] {db_path}: not found")
        return []
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT 姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间 FROM records"
    ).fetchall()
    conn.close()
    records = []
    for r in rows:
        records.append({
            "name": r[0] or "", "gender": r[1] or "", "age": r[2] or "",
            "serial": r[3] or "", "bullet": r[4] or "", "time": r[5] or "",
            "dept": r[6] or "", "bed": r[7] or "", "ocr": r[8] or "", "saved": r[9] or "",
            "source_db": db_path, "source_cap": cap_dir,
        })
    return records

def main():
    parser = argparse.ArgumentParser(
        description="Merge EDTA-OCR databases",
        epilog="Example input file (paths.txt):\n"
               "  path1/edta_ocr.db path1/captures\n"
               "  path2/edta_ocr.db path2/captures")
    parser.add_argument("input_file",
                        help="File with one 'db_path captures_dir' pair per line, or --db/--captures")
    parser.add_argument("--force", action="store_true",
                        help="Actually perform the merge (without this, only report conflicts)")
    parser.add_argument("--keep-duplicates", action="store_true",
                        help="Keep all records even when bullet numbers conflict (drops UNIQUE constraint)")
    parser.add_argument("--out", default="merged.db", help="Output merged database")
    parser.add_argument("--out-captures", default="merged_captures",
                        help="Output captures directory")
    args = parser.parse_args()

    # Parse input file
    dbs, caps = [], []
    with open(args.input_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                dbs.append(parts[0])
                caps.append(parts[1])
            else:
                print(f"  [SKIP] invalid line: {line}")

    if not dbs:
        print("Error: no valid entries in input file", file=sys.stderr)
        sys.exit(1)

    # Load all databases
    print("Loading databases...")
    all_sources = []
    for db_path, cap_dir in zip(dbs, caps):
        records = load_db(db_path, cap_dir)
        if records:
            all_sources.append((db_path, cap_dir, records))
            print(f"  {db_path}: {len(records)} records")

    # Find conflicts: same bullet number in multiple DBs
    print("\nChecking for conflicts...")
    seen = OrderedDict()  # bullet -> list of (db_path, record)
    for db_path, cap_dir, records in all_sources:
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
            names = [f"{e[1]['name']}" for e in entries]
            dbs = [e[0] for e in entries]
            saved_times = [e[1]["saved"] for e in entries]
            print(f"\n  Bullet {b}:")
            for (db, rec), saved in zip(entries, saved_times):
                print(f"    {db}: 姓名={rec['name']} 住院号={rec['serial']} 录入={saved}")
    else:
        print("  No conflicts found.")

    total_singletons = sum(1 for b in singletons if b)
    total_conflicts = len(conflicts)
    conflict_records = sum(len(v) for v in conflicts.values())
    print(f"\nSummary: {total_singletons} unique records, {total_conflicts} conflicting bullets ({conflict_records} total records involved)")

    if not args.force:
        if conflicts:
            dup_flag = " --keep-duplicates" if args.keep_duplicates else ""
            if args.keep_duplicates:
                print("\nRun with --force --keep-duplicates to merge (all records kept, duplicates allowed).")
            else:
                print("\nRun with --force to merge (last --db wins on conflict).")
            print("         --keep-duplicates to keep all conflicting records instead.")
        else:
            print("\nNo conflicts. Run with --force to proceed with merge.")
        return

    # --- Force merge ---
    print("\nMerging...")
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    os.makedirs(args.out_captures, exist_ok=True)

    out_db = sqlite3.connect(args.out)
    out_db.execute("DROP TABLE IF EXISTS records")
    unique_clause = "" if args.keep_duplicates else "UNIQUE"
    out_db.execute(f"""
        CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            姓名 TEXT, 性别 TEXT, 年龄 TEXT, 住院号 TEXT,
            子弹头编号 TEXT {unique_clause}, 采血时间 TEXT,
            科室 TEXT, 床号 TEXT, 原始OCR文本 TEXT,
            录入时间 TEXT DEFAULT (datetime('now','localtime'))
        )
    """)

    merged = 0
    # Insert singletons (no conflict, just insert)
    for b, (db_path, rec) in singletons.items():
        out_db.execute("DELETE FROM records WHERE 子弹头编号 = ?", (b,))
        out_db.execute(
            "INSERT INTO records (姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (rec["name"], rec["gender"], rec["age"], rec["serial"], b,
             rec["time"], rec["dept"], rec["bed"], rec["ocr"], rec["saved"])
        )
        merged += 1

    # Insert conflicts
    if args.keep_duplicates:
        # Keep all records — insert every entry for each conflicting bullet
        for b, entries in conflicts.items():
            for _db_path, rec in entries:
                out_db.execute(
                    "INSERT INTO records (姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    (rec["name"], rec["gender"], rec["age"], rec["serial"], b,
                     rec["time"], rec["dept"], rec["bed"], rec["ocr"], rec["saved"])
                )
                merged += 1
    else:
        # Last --db wins (default)
        for b, entries in conflicts.items():
            _, winner = entries[-1]  # last entry wins
            out_db.execute("DELETE FROM records WHERE 子弹头编号 = ?", (b,))
            out_db.execute(
                "INSERT INTO records (姓名,性别,年龄,住院号,子弹头编号,采血时间,科室,床号,原始OCR文本,录入时间) VALUES (?,?,?,?,?,?,?,?,?,?)",
                (winner["name"], winner["gender"], winner["age"], winner["serial"], b,
                 winner["time"], winner["dept"], winner["bed"], winner["ocr"], winner["saved"])
            )
            merged += 1

    out_db.commit()
    out_db.close()

    # Copy images from all sources
    img_count = 0
    img_skipped = 0
    for db_path, cap_dir, _ in all_sources:
        if not os.path.isdir(cap_dir):
            continue
        for dirpath, _dirnames, filenames in os.walk(cap_dir):
            for fname in filenames:
                if not fname.endswith(".png"):
                    continue
                # Skip _latest.png — it is a transient app file, not tied to
                # any bullet number, and would overwrite the previous source's
                # _latest.png (which may be the only surviving image for a
                # record whose numbered PNG was never saved).
                if fname == "_latest.png":
                    continue
                src = os.path.join(dirpath, fname)
                dst = os.path.join(args.out_captures, fname)
                if os.path.exists(dst):
                    img_skipped += 1
                    if args.force:
                        shutil.copy2(src, dst)
                else:
                    shutil.copy2(src, dst)
                    img_count += 1

    # Recovery: for records whose bullet image is still missing, check if the
    # source's _latest.png is the only surviving image.  The macOS app always
    # saves a numbered PNG *and* _latest.png, but if the app crashed mid-save
    # the numbered file may never have been written.
    recovered = 0
    for b in singletons:
        dst_path = os.path.join(args.out_captures, f"{b}.png")
        if os.path.exists(dst_path):
            continue
        _db_path, rec = singletons[b]
        src_cap = rec.get("source_cap", "")
        if not src_cap:
            continue
        for dirpath, _dirnames, filenames in os.walk(src_cap):
            if "_latest.png" in filenames:
                src = os.path.join(dirpath, "_latest.png")
                shutil.copy2(src, dst_path)
                recovered += 1
                break
    for b in conflicts:
        dst_path = os.path.join(args.out_captures, f"{b}.png")
        if os.path.exists(dst_path):
            continue
        _, winner = conflicts[b][-1]
        src_cap = winner.get("source_cap", "")
        if not src_cap:
            continue
        for dirpath, _dirnames, filenames in os.walk(src_cap):
            if "_latest.png" in filenames:
                src = os.path.join(dirpath, "_latest.png")
                shutil.copy2(src, dst_path)
                recovered += 1
                break

    if recovered:
        print(f"  {recovered} images recovered from _latest.png fallback")

    print(f"  {merged} records written to {args.out}")
    print(f"  {img_count} images copied, {img_skipped} overwritten in {args.out_captures}/")
    print("Done.")

if __name__ == "__main__":
    main()
