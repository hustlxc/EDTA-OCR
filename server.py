#!/usr/bin/env python3
"""Web viewer for EDTA-OCR merged database and captures."""

import sqlite3
import os
from flask import Flask, g, jsonify, request, render_template, send_file

DB_PATH = "merged_db-2026-06-17.db"
CAPTURES_DIR = "merged_captures-2026-06-17"
PER_PAGE = 40

app = Flask(__name__)


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exception=None):
    db = g.pop("db", None)
    if db:
        db.close()


# ── Routes ────────────────────────────────────────────────────────────────


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/departments")
def api_departments():
    db = get_db()
    rows = db.execute(
        "SELECT 科室, COUNT(*) AS cnt FROM records WHERE 科室 != '' GROUP BY 科室 ORDER BY cnt DESC"
    ).fetchall()
    return jsonify([{"name": r["科室"], "count": r["cnt"]} for r in rows])


@app.route("/api/stats")
def api_stats():
    db = get_db()
    total = db.execute("SELECT COUNT(*) FROM records").fetchone()[0]
    has_img = db.execute(
        "SELECT COUNT(*) FROM records WHERE 子弹头编号 != ''"
    ).fetchone()[0]
    return jsonify({"total": total, "with_bullet": has_img})


@app.route("/api/records")
def api_records():
    db = get_db()

    search = request.args.get("q", "").strip()
    dept = request.args.get("dept", "").strip()
    page = max(1, int(request.args.get("page", 1)))

    conditions = []
    params = []

    if search:
        conditions.append(
            "(姓名 LIKE ? OR 住院号 LIKE ? OR 子弹头编号 LIKE ? OR 床号 LIKE ?)"
        )
        like = f"%{search}%"
        params.extend([like, like, like, like])

    if dept:
        conditions.append("科室 = ?")
        params.append(dept)

    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""

    # count
    count = db.execute(
        f"SELECT COUNT(*) FROM records {where}", params
    ).fetchone()[0]

    total_pages = max(1, (count + PER_PAGE - 1) // PER_PAGE)
    page = min(page, total_pages)
    offset = (page - 1) * PER_PAGE

    rows = db.execute(
        f"SELECT * FROM records {where} ORDER BY id LIMIT ? OFFSET ?",
        params + [PER_PAGE, offset],
    ).fetchall()

    records = []
    for r in rows:
        bullet = r["子弹头编号"] or ""
        has_image = os.path.exists(
            os.path.join(CAPTURES_DIR, f"{bullet}.png")
        ) if bullet else False
        records.append(
            {
                "id": r["id"],
                "name": r["姓名"] or "",
                "gender": r["性别"] or "",
                "age": r["年龄"] or "",
                "serial": r["住院号"] or "",
                "bullet": bullet,
                "time": r["采血时间"] or "",
                "dept": r["科室"] or "",
                "bed": r["床号"] or "",
                "ocr": r["原始OCR文本"] or "",
                "saved": r["录入时间"] or "",
                "has_image": has_image,
            }
        )

    return jsonify(
        {
            "records": records,
            "page": page,
            "total_pages": total_pages,
            "total": count,
        }
    )


@app.route("/api/record/<int:record_id>")
def api_record(record_id):
    db = get_db()
    r = db.execute("SELECT * FROM records WHERE id = ?", (record_id,)).fetchone()
    if not r:
        return jsonify({"error": "Not found"}), 404
    bullet = r["子弹头编号"] or ""
    return jsonify(
        {
            "id": r["id"],
            "name": r["姓名"] or "",
            "gender": r["性别"] or "",
            "age": r["年龄"] or "",
            "serial": r["住院号"] or "",
            "bullet": bullet,
            "time": r["采血时间"] or "",
            "dept": r["科室"] or "",
            "bed": r["床号"] or "",
            "ocr": r["原始OCR文本"] or "",
            "saved": r["录入时间"] or "",
        }
    )


@app.route("/captures/<filename>")
def serve_image(filename):
    # sanitize: only allow .png files with numeric names
    if not filename.endswith(".png"):
        return "Bad filename", 400
    path = os.path.join(CAPTURES_DIR, filename)
    if not os.path.exists(path):
        return "Not found", 404
    return send_file(path, mimetype="image/png")


if __name__ == "__main__":
    os.makedirs("templates", exist_ok=True)
    print(f"Database: {DB_PATH} ({os.path.getsize(DB_PATH)/1024/1024:.1f} MB)")
    print(f"Captures: {CAPTURES_DIR}/")
    print("\nStarting server at http://localhost:5000")
    app.run(host="0.0.0.0", port=8087, debug=True)
