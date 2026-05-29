#!/usr/bin/env python3
"""PP-OCRv5 daemon — long-lived OCR process for EDTA tube labels.

Listens on stdin for image paths (one per line), outputs JSON to stdout.
Send "exit" to quit.

Requires: pip install paddlepaddle paddleocr
"""

import sys
import json
import os

try:
    from paddleocr import PaddleOCR
except ImportError:
    print(json.dumps({"status": "error", "message": "PaddleOCR not installed. Run: pip3 install paddlepaddle paddleocr"}),
          flush=True)
    sys.exit(1)

# Load models once at startup
try:
    ocr = PaddleOCR(
        text_detection_model_name="PP-OCRv5_server_det",
        text_recognition_model_name="PP-OCRv5_server_rec",
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        lang="ch",
    )
except Exception as e:
    print(json.dumps({"status": "error", "message": f"Failed to load PP-OCRv5: {e}"}), flush=True)
    sys.exit(1)

# Signal ready — Swift will wait for this line
print(json.dumps({"status": "ready"}), flush=True)

# Main loop: read image paths from stdin, output results
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if line == "ping":
        print(json.dumps({"status": "pong"}), flush=True)
        continue
    if line == "exit":
        break

    if not os.path.exists(line):
        print(json.dumps({"status": "error", "message": f"File not found: {line}"}), flush=True)
        continue

    try:
        result = ocr.predict(line)
        items = []
        for res in result:
            rec_texts = res.get("rec_texts", [])
            rec_scores = res.get("rec_scores", [])
            dt_polys = res.get("dt_polys", [])

            for i, (text, score) in enumerate(zip(rec_texts, rec_scores)):
                poly = dt_polys[i] if i < len(dt_polys) else [[0, 0], [0, 0], [0, 0], [0, 0]]
                items.append({
                    "text": text,
                    "confidence": float(score),
                    "bbox": {
                        "x": float(poly[0][0]),
                        "y": float(poly[0][1]),
                        "w": float(poly[2][0] - poly[0][0]) if len(poly) >= 3 else 0,
                        "h": float(poly[2][1] - poly[0][1]) if len(poly) >= 3 else 0,
                    }
                })

        print(json.dumps({"status": "ok", "results": items}), flush=True)
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}), flush=True)
