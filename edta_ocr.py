#!/usr/bin/env python3
"""EDTA 采血管 OCR 录入系统 — 使用 Mac 原生 Vision 框架 + AVFoundation 摄像头"""

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import subprocess
import json
import sqlite3
import threading
import os
from datetime import datetime

# ============================================================
# DatabaseManager
# ============================================================

class DatabaseManager:
    def __init__(self, db_path="edta_ocr.db"):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self._init_table()

    def _init_table(self):
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                姓名 TEXT DEFAULT '',
                性别 TEXT DEFAULT '',
                年龄 TEXT DEFAULT '',
                barcode TEXT DEFAULT '',
                采血时间 TEXT DEFAULT '',
                科室 TEXT DEFAULT '',
                床号 TEXT DEFAULT '',
                录入数据库时间 TEXT DEFAULT (datetime('now','localtime'))
            )
        """)
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_records_barcode ON records(barcode)")
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_records_time ON records(录入数据库时间)")
        self.conn.commit()

    def insert_record(self, fields):
        cursor = self.conn.execute("""
            INSERT INTO records (姓名, 性别, 年龄, barcode, 采血时间, 科室, 床号)
            VALUES (:姓名, :性别, :年龄, :barcode, :采血时间, :科室, :床号)
        """, fields)
        self.conn.commit()
        return cursor.lastrowid

    def get_recent(self, limit=50):
        rows = self.conn.execute(
            "SELECT * FROM records ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [dict(r) for r in rows]

    def count(self):
        return self.conn.execute("SELECT COUNT(*) FROM records").fetchone()[0]

    def close(self):
        self.conn.close()


# ============================================================
# FieldExtractor
# ============================================================

class FieldExtractor:
    # Labels often differ between hospitals; cover common variants
    FIELD_PATTERNS = {
        "姓名": [
            r'姓名[\s:：]*([^  \t:：]{2,8})',
            r'患者[姓名称][\s:：]*([^  \t:：]{2,8})',
            r'Name[\s:：]*([A-Za-z一-鿿]{2,20})',
        ],
        "性别": [
            r'性别[\s:：]*([男女])',
            r'[Ss]ex[\s:：]*([MFmf男女])',
        ],
        "年龄": [
            r'年龄[\s:：]*(\d+)',
            r'(\d+)\s*岁',
            r'[Aa]ge[\s:：]*(\d+)',
        ],
        "科室": [
            r'科室[\s:：]*([^\s:：]{2,12})',
            r'[Dd]ept[\s.:：]*([^\s:：]{2,12})',
        ],
        "床号": [
            r'床号[\s:：]*([^\s:：]{1,10})',
            r'(\d+[#号]?\s*床)',
            r'[Bb]ed[\s.:：]*([^\s:：]{1,10})',
        ],
        "采血时间": [
            r'采血时间[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2})',
            r'采血时间[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2})',
            r'采血日期[\s:：]*(\d{4}[-/]\d{1,2}[-/]\d{1,2})',
            r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}:\d{2})',
            r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2})',
            r'(\d{4}[-/]\d{1,2}[-/]\d{1,2})',
        ],
    }

    BARCODE_PATTERNS = [
        r'(\d{10,20})',                # all digits
        r'([A-Z0-9]{8,20})',           # alphanumeric
    ]

    def __init__(self):
        import re
        self._field_regex = {}
        for field, patterns in self.FIELD_PATTERNS.items():
            self._field_regex[field] = [re.compile(p) for p in patterns]
        self._barcode_regex = [re.compile(p) for p in self.BARCODE_PATTERNS]

    def extract(self, ocr_results):
        """Parse a list of {text, confidence, bbox} dicts into structured fields.

        Returns dict of {field_name: {"value": str, "confidence": str}}.
        Confidence is "high" | "medium" | "low".
        """
        import re  # ensure re is available in method scope

        if not ocr_results:
            return self._empty_result()

        # Filter low-confidence results and sort by y descending (top to bottom)
        filtered = [r for r in ocr_results if r.get("confidence", 0) > 0.2]
        if not filtered:
            return self._empty_result()

        filtered.sort(key=lambda r: -r["bbox"]["y"])

        # Group into rows (y within 3% threshold)
        rows = self._group_rows(filtered)
        # For each row, sort by x (left to right) and concatenate
        row_texts = []
        for row in rows:
            row.sort(key=lambda r: r["bbox"]["x"])
            combined = "  ".join(r["text"] for r in row)
            row_texts.append(combined)

        full_text = "\n".join(row_texts)

        result = {}
        matched_texts = set()

        # Pass 1: named field patterns
        for field, patterns in self._field_regex.items():
            for pat in patterns:
                m = pat.search(full_text)
                if m:
                    value = m.group(1).strip()
                    if value:
                        # Determine confidence based on which pattern matched
                        conf = self._ocr_confidence(filtered, m.group(0), field)
                        result[field] = {"value": value, "confidence": conf}
                        matched_texts.add(m.group(0))
                        break

        # Pass 2: barcode detection (digit-heavy sequence not already matched)
        for r in filtered:
            text = r["text"].strip()
            # Skip texts already consumed
            if any(text in mt or mt in text for mt in matched_texts):
                continue
            for pat in self._barcode_regex:
                bm = pat.fullmatch(text)
                if bm and len(bm.group(1)) >= 8:
                    conf_raw = r.get("confidence", 0)
                    if conf_raw > 0.8:
                        conf = "high"
                    elif conf_raw > 0.5:
                        conf = "medium"
                    else:
                        conf = "low"
                    result["barcode"] = {"value": bm.group(1), "confidence": conf}
                    matched_texts.add(text)
                    break
            if "barcode" in result:
                break

        # Post-process: normalize gender
        if "性别" in result:
            v = result["性别"]["value"]
            if v in ("M", "m"):
                result["性别"]["value"] = "男"
            elif v in ("F", "f"):
                result["性别"]["value"] = "女"

        # Fill in any missing fields as empty
        for field in ["姓名", "性别", "年龄", "barcode", "采血时间", "科室", "床号"]:
            if field not in result:
                result[field] = {"value": "", "confidence": "low"}

        result["_raw_text"] = full_text
        return result

    def _group_rows(self, results):
        """Group OCR results by row (similar y coordinates)."""
        if not results:
            return []
        rows = []
        used = set()
        for i, r in enumerate(results):
            if i in used:
                continue
            row = [r]
            used.add(i)
            ry = r["bbox"]["y"]
            for j, r2 in enumerate(results):
                if j in used:
                    continue
                if abs(r2["bbox"]["y"] - ry) < 0.03:
                    row.append(r2)
                    used.add(j)
            rows.append(row)
        return rows

    def _ocr_confidence(self, results, matched_text, field):
        """Estimate confidence level for a matched field."""
        best_conf = 0.0
        for r in results:
            if r["text"].strip() in matched_text or matched_text in r["text"]:
                if r["confidence"] > best_conf:
                    best_conf = r["confidence"]
        if best_conf > 0.8:
            return "high"
        elif best_conf > 0.5:
            return "medium"
        return "low"

    def _empty_result(self):
        result = {}
        for field in ["姓名", "性别", "年龄", "barcode", "采血时间", "科室", "床号"]:
            result[field] = {"value": "", "confidence": "low"}
        result["_raw_text"] = ""
        return result


# ============================================================
# GUI Application
# ============================================================

class EDTAApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("EDTA 采血管 OCR 录入系统")
        self.root.minsize(960, 680)
        self.root.configure(bg="#f0f0f5")

        # Style
        self.style = ttk.Style()
        self.style.theme_use("clam")
        self.style.configure("Title.TLabel", font=("Helvetica", 22, "bold"),
                             foreground="#1a1a2e", background="#f0f0f5")
        self.style.configure("Subtitle.TLabel", font=("Helvetica", 13),
                             foreground="#555", background="#f0f0f5")
        self.style.configure("FieldName.TLabel", font=("Helvetica", 13, "bold"),
                             foreground="#333", background="white")
        self.style.configure("HighConf.TLabel", foreground="#2d8a4e", font=("Helvetica", 11))
        self.style.configure("MediumConf.TLabel", foreground="#b8860b", font=("Helvetica", 11))
        self.style.configure("LowConf.TLabel", foreground="#c0392b", font=("Helvetica", 11))

        # Large action button
        self.style.configure("Action.TButton", font=("Helvetica", 16, "bold"), padding=12)

        self.db = DatabaseManager(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                "edta_ocr.db"))
        self.extractor = FieldExtractor()

        self.current_frame = None
        self.capture_result = None
        self.current_image_path = None
        self.ocr_results = None
        self.extracted_fields = None
        self.last_saved = None

        self._build_home_screen()
        self._build_review_screen()
        self._build_confirm_screen()
        self._build_history_screen()

        self.show_frame("home")

    # ---- Frame switching ----

    def show_frame(self, name):
        if self.current_frame:
            self.current_frame.pack_forget()

        frame = self._frames.get(name)
        if frame is None:
            return

        if name == "home":
            self._update_home_stats()
        elif name == "history":
            self._refresh_history()

        frame.pack(fill="both", expand=True)
        self.current_frame = frame

    # ---- Home Screen ----

    def _build_home_screen(self):
        if not hasattr(self, "_frames"):
            self._frames = {}

        frame = tk.Frame(self.root, bg="#f0f0f5")
        self._frames["home"] = frame

        # Center container
        center = tk.Frame(frame, bg="#f0f0f5")
        center.place(relx=0.5, rely=0.45, anchor="center")

        ttk.Label(center, text="EDTA 采血管 OCR 录入系统",
                  style="Title.TLabel").pack(pady=(0, 4))
        ttk.Label(center, text="Blood Collection Tube OCR",
                  style="Subtitle.TLabel").pack(pady=(0, 30))

        self.capture_btn = tk.Button(
            center, text="打开摄像头并拍照",
            font=("Helvetica", 17, "bold"), fg="white", bg="#2563eb",
            activeforeground="white", activebackground="#1d4ed8",
            relief="flat", padx=40, pady=16,
            cursor="pointinghand", command=self._on_capture
        )
        self.capture_btn.pack(pady=(0, 24))

        self.home_status_label = ttk.Label(
            center, text="状态: 就绪",
            font=("Helvetica", 12), foreground="#666", background="#f0f0f5"
        )
        self.home_status_label.pack(pady=(0, 8))

        self.home_count_label = ttk.Label(
            center, text="已录入: 0 条",
            font=("Helvetica", 12), foreground="#666", background="#f0f0f5"
        )
        self.home_count_label.pack(pady=(0, 28))

        history_btn = tk.Button(
            center, text="查看历史记录",
            font=("Helvetica", 12), fg="#2563eb", bg="#f0f0f5",
            relief="flat", cursor="pointinghand",
            command=lambda: self.show_frame("history")
        )
        history_btn.pack()

    def _update_home_stats(self):
        count = self.db.count()
        self.home_count_label.config(text=f"已录入: {count} 条")
        self.home_status_label.config(text="状态: 就绪")
        self.capture_btn.config(state="normal")

    # ---- Review Screen ----

    def _build_review_screen(self):
        frame = tk.Frame(self.root, bg="white")
        self._frames["review"] = frame

        # Top bar
        top_bar = tk.Frame(frame, bg="#f8f9fa", height=48)
        top_bar.pack(fill="x")
        back_btn = tk.Button(top_bar, text="← 返回", font=("Helvetica", 12),
                             fg="#555", bg="#f8f9fa", relief="flat",
                             cursor="pointinghand",
                             command=lambda: self.show_frame("home"))
        back_btn.pack(side="left", padx=12, pady=8)

        ttk.Label(top_bar, text="审核识别结果", font=("Helvetica", 14, "bold"),
                  foreground="#333", background="#f8f9fa").pack(side="left", padx=12, pady=8)

        self.review_timestamp_label = ttk.Label(
            top_bar, text="", font=("Helvetica", 11),
            foreground="#888", background="#f8f9fa"
        )
        self.review_timestamp_label.pack(side="right", padx=16, pady=8)

        # Main content
        content = tk.Frame(frame, bg="white")
        content.pack(fill="both", expand=True, padx=0)

        # Left: Image
        image_frame = tk.Frame(content, bg="#e8e8e8", width=460, height=540)
        image_frame.pack(side="left", fill="both", expand=True, padx=(16, 8), pady=16)
        image_frame.pack_propagate(False)

        self.image_label = tk.Label(image_frame, bg="#e8e8e8", text="拍摄的图片",
                                     font=("Helvetica", 14), fg="#888")
        self.image_label.pack(expand=True)

        # Right: Form
        form_frame = tk.Frame(content, bg="white")
        form_frame.pack(side="right", fill="both", expand=True, padx=(8, 16), pady=16)

        # Scrollable form area
        form_canvas = tk.Canvas(form_frame, bg="white", highlightthickness=0)
        form_scroll = ttk.Scrollbar(form_frame, orient="vertical", command=form_canvas.yview)
        form_inner = tk.Frame(form_canvas, bg="white")

        form_inner.bind("<Configure>", lambda e: form_canvas.configure(
            scrollregion=form_canvas.bbox("all")))
        form_canvas.create_window((0, 0), window=form_inner, anchor="nw")
        form_canvas.configure(yscrollcommand=form_scroll.set)

        form_canvas.pack(side="left", fill="both", expand=True)
        form_scroll.pack(side="right", fill="y")

        # Mouse wheel scrolling
        def _on_mousewheel(event):
            form_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        form_canvas.bind_all("<MouseWheel>", _on_mousewheel)

        # Field entries
        self.field_vars = {}
        self.conf_labels = {}
        fields_config = [
            ("姓名", None),
            ("性别", ["男", "女"]),
            ("年龄", None),
            ("barcode", None),
            ("采血时间", None),
            ("科室", None),
            ("床号", None),
        ]

        for field_name, options in fields_config:
            row = tk.Frame(form_inner, bg="white")
            row.pack(fill="x", pady=8)

            ttk.Label(row, text=f"{field_name}:", style="FieldName.TLabel",
                      width=9, anchor="e").pack(side="left", padx=(0, 8))

            var = tk.StringVar()
            self.field_vars[field_name] = var

            if options:
                widget = ttk.Combobox(row, textvariable=var, values=options,
                                       font=("Helvetica", 14), state="readonly", width=18)
            else:
                widget = ttk.Entry(row, textvariable=var,
                                    font=("Helvetica", 14), width=20)
            widget.pack(side="left")

            conf_label = ttk.Label(row, text="", style="LowConf.TLabel")
            conf_label.pack(side="left", padx=(10, 0))
            self.conf_labels[field_name] = conf_label

        # Raw OCR text
        raw_section = tk.Frame(form_inner, bg="white")
        raw_section.pack(fill="x", pady=(16, 8))

        ttk.Label(raw_section, text="原始 OCR 文本:",
                  font=("Helvetica", 11, "bold"), foreground="#666",
                  background="white").pack(anchor="w")

        self.raw_text = scrolledtext.ScrolledText(
            raw_section, height=5, font=("Helvetica", 11), wrap="word",
            state="disabled", bg="#f9f9f9", relief="solid", borderwidth=1
        )
        self.raw_text.pack(fill="x", pady=(4, 0))

        # Bottom buttons
        btn_row = tk.Frame(frame, bg="white", height=60)
        btn_row.pack(fill="x", side="bottom", pady=(8, 16))

        recapture_btn = tk.Button(
            btn_row, text="重新拍照", font=("Helvetica", 13),
            fg="#555", bg="#e0e0e0", relief="flat", padx=28, pady=10,
            cursor="pointinghand", command=self._on_capture
        )
        recapture_btn.pack(side="left", padx=(50, 0))

        self.save_btn = tk.Button(
            btn_row, text="确认保存", font=("Helvetica", 14, "bold"),
            fg="white", bg="#16a34a", activeforeground="white",
            activebackground="#15803d",
            relief="flat", padx=36, pady=10,
            cursor="pointinghand", command=self._on_save
        )
        self.save_btn.pack(side="right", padx=(0, 50))

    def _populate_review_form(self, fields):
        for name, var in self.field_vars.items():
            if name in fields:
                var.set(fields[name]["value"])
                conf = fields[name]["confidence"]
                self._set_confidence_label(name, conf, fields[name]["value"] != "")
            else:
                var.set("")
                self._set_confidence_label(name, "low", False)

        # Raw text
        self.raw_text.config(state="normal")
        self.raw_text.delete("1.0", "end")
        raw = fields.get("_raw_text", "")
        self.raw_text.insert("1.0", raw if raw else "(未识别到文字)")
        self.raw_text.config(state="disabled")

    def _set_confidence_label(self, field, conf, has_value):
        label = self.conf_labels[field]
        if not has_value:
            label.config(text="未识别", style="LowConf.TLabel")
            return
        if conf == "high":
            label.config(text="●", style="HighConf.TLabel")
        elif conf == "medium":
            label.config(text="●", style="MediumConf.TLabel")
        else:
            label.config(text="●", style="LowConf.TLabel")

    # ---- Confirm Screen ----

    def _build_confirm_screen(self):
        frame = tk.Frame(self.root, bg="#f0fdf4")
        self._frames["confirm"] = frame

        center = tk.Frame(frame, bg="#f0fdf4")
        center.place(relx=0.5, rely=0.4, anchor="center")

        # Success icon
        check_label = tk.Label(center, text="✓", font=("Helvetica", 48, "bold"),
                               fg="#16a34a", bg="#f0fdf4")
        check_label.pack(pady=(0, 8))

        ttk.Label(center, text="保存成功",
                  font=("Helvetica", 20, "bold"),
                  foreground="#15803d", background="#f0fdf4").pack(pady=(0, 20))

        # Summary
        self.confirm_text = scrolledtext.ScrolledText(
            center, height=9, width=42, font=("Helvetica", 13),
            wrap="word", state="disabled",
            bg="#f9fcf9", relief="solid", borderwidth=1
        )
        self.confirm_text.pack(pady=(0, 24))

        # Action buttons
        btn_row = tk.Frame(center, bg="#f0fdf4")
        btn_row.pack()

        tk.Button(btn_row, text="继续录入", font=("Helvetica", 13),
                  fg="white", bg="#2563eb", relief="flat", padx=28, pady=10,
                  cursor="pointinghand",
                  command=lambda: self.show_frame("home")).pack(side="left", padx=8)

        tk.Button(btn_row, text="查看历史", font=("Helvetica", 13),
                  fg="#2563eb", bg="white", relief="solid", borderwidth=1,
                  padx=28, pady=10, cursor="pointinghand",
                  command=lambda: self.show_frame("history")).pack(side="left", padx=8)

    def _show_confirm(self, fields):
        self.confirm_text.config(state="normal")
        self.confirm_text.delete("1.0", "end")
        lines = [
            f"姓名: {fields.get('姓名', '')}",
            f"性别: {fields.get('性别', '')}    年龄: {fields.get('年龄', '')}",
            f"条形码: {fields.get('barcode', '')}",
            f"科室: {fields.get('科室', '')}    床号: {fields.get('床号', '')}",
            f"采血时间: {fields.get('采血时间', '')}",
            f"录入时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        ]
        self.confirm_text.insert("1.0", "\n".join(lines))
        self.confirm_text.config(state="disabled")
        self.show_frame("confirm")

    # ---- History Screen ----

    def _build_history_screen(self):
        frame = tk.Frame(self.root, bg="white")
        self._frames["history"] = frame

        # Top bar
        top_bar = tk.Frame(frame, bg="#f8f9fa", height=48)
        top_bar.pack(fill="x")

        back_btn = tk.Button(top_bar, text="← 返回", font=("Helvetica", 12),
                             fg="#555", bg="#f8f9fa", relief="flat",
                             cursor="pointinghand",
                             command=lambda: self.show_frame("home"))
        back_btn.pack(side="left", padx=12, pady=8)

        ttk.Label(top_bar, text="历史记录", font=("Helvetica", 14, "bold"),
                  foreground="#333", background="#f8f9fa").pack(side="left", padx=12, pady=8)

        self.history_count_label = ttk.Label(
            top_bar, text="", font=("Helvetica", 11),
            foreground="#888", background="#f8f9fa"
        )
        self.history_count_label.pack(side="right", padx=16, pady=8)

        # Treeview
        tree_frame = tk.Frame(frame, bg="white")
        tree_frame.pack(fill="both", expand=True, padx=16, pady=8)

        columns = ("id", "姓名", "性别", "年龄", "barcode", "采血时间", "科室", "床号", "录入数据库时间")
        self.tree = ttk.Treeview(tree_frame, columns=columns, show="headings",
                                  selectmode="browse")

        col_widths = [40, 80, 50, 50, 130, 150, 80, 70, 150]
        for col, width in zip(columns, col_widths):
            self.tree.heading(col, text=col)
            self.tree.column(col, width=width, anchor="center")

        scrollbar = ttk.Scrollbar(tree_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)

        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

    def _refresh_history(self):
        for item in self.tree.get_children():
            self.tree.delete(item)

        records = self.db.get_recent(100)
        for r in records:
            values = tuple(str(r.get(col, "")) for col in
                          ("id", "姓名", "性别", "年龄", "barcode",
                           "采血时间", "科室", "床号", "录入数据库时间"))
            self.tree.insert("", "end", values=values)

        self.history_count_label.config(text=f"共 {len(records)} 条")

    # ---- Capture + OCR Flow ----

    def _on_capture(self):
        tool_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capture_tool")
        if not os.path.exists(tool_path):
            messagebox.showerror("错误", "未找到 capture_tool 程序。\n请先运行 build_and_run.sh 编译。")
            return

        if self.current_frame:
            self.home_status_label.config(text="状态: 摄像头已启动，请在弹出窗口中操作...")
        else:
            self.home_status_label.config(text="状态: 摄像头已启动...")
        self.capture_btn.config(state="disabled")
        self.root.update()

        thread = threading.Thread(target=self._run_swift_tool, args=(tool_path,), daemon=True)
        thread.start()
        self._poll_capture_thread(thread)

    def _run_swift_tool(self, tool_path):
        try:
            proc = subprocess.run(
                [tool_path],
                capture_output=True, text=True, timeout=120
            )
            self.capture_result = proc
        except subprocess.TimeoutExpired:
            self.capture_result = None
        except Exception as e:
            self.capture_result = e

    def _poll_capture_thread(self, thread):
        if thread.is_alive():
            self.root.after(200, lambda: self._poll_capture_thread(thread))
            return

        result = self.capture_result

        if result is None:
            messagebox.showerror("错误", "摄像头操作超时")
            self.show_frame("home")
            return
        if isinstance(result, Exception):
            messagebox.showerror("错误", f"启动摄像头失败:\n{result}")
            self.show_frame("home")
            return

        # Parse output
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            # Try to find JSON in stderr or output
            messagebox.showerror("错误",
                f"无法解析 OCR 结果。\nstdout: {result.stdout[:200]}\nstderr: {result.stderr[:200]}")
            self.show_frame("home")
            return

        if not data.get("success"):
            error_msg = data.get("message", "未知错误")
            error_code = data.get("error", "")
            if error_code == "permission_denied":
                messagebox.showinfo("摄像头权限",
                    "请在 系统设置 > 隐私与安全性 > 摄像头 中允许终端访问摄像头。")
            elif error_code == "cancelled":
                # User cancelled; just go back home silently
                self.show_frame("home")
                return
            else:
                messagebox.showerror("OCR 错误", error_msg)
            self.show_frame("home")
            return

        # Success - populate review form
        self.current_image_path = data.get("image_path")
        self.ocr_results = data.get("ocr_results", [])

        # Extract fields
        fields = self.extractor.extract(self.ocr_results)
        self.extracted_fields = fields

        # Load image
        if self.current_image_path and os.path.exists(self.current_image_path):
            self._display_captured_image(self.current_image_path)

        # Populate form
        self._populate_review_form(fields)

        # Update timestamp
        captured_at = data.get("captured_at", "")
        self.review_timestamp_label.config(text=f"拍摄时间: {captured_at}" if captured_at else "")

        self.show_frame("review")

    def _display_captured_image(self, path):
        try:
            img = tk.PhotoImage(file=path)
            w = img.width()
            if w > 440:
                factor = max(1, w // 440)
                img = img.subsample(factor, factor)
            self.image_label.config(image=img, text="", bg="#e8e8e8")
            self.image_label.image = img  # Keep reference
        except Exception:
            self.image_label.config(text="(无法加载图片)", image="", bg="#e8e8e8")

    # ---- Save Flow ----

    def _on_save(self):
        fields = {}
        for name in ["姓名", "性别", "年龄", "barcode", "采血时间", "科室", "床号"]:
            fields[name] = self.field_vars[name].get().strip()

        if not fields["姓名"]:
            messagebox.showwarning("验证提示", "姓名不能为空，请填写后再保存。")
            return

        try:
            self.db.insert_record(fields)
        except sqlite3.Error as e:
            messagebox.showerror("数据库错误", f"保存失败:\n{e}")
            return

        self._show_confirm(fields)

    # ---- Run ----

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    app = EDTAApp()
    app.run()
