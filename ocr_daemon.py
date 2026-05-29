#!/usr/bin/env python3
"""PP-OCRv5 daemon — long-lived OCR process using file-based IPC.

Watches /tmp/ocr_request.txt for image paths. Each line is an image path.
Writes results to /tmp/ocr_response.json (one JSON per request).
Signal file /tmp/ocr_ready indicates daemon is loaded.
Delete /tmp/ocr_request.txt to stop, or send "exit" on stdin.
"""

import sys, json, os, time, logging

logging.basicConfig(stream=sys.stderr, level=logging.WARNING, format="%(message)s")
os.environ["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"

try:
    from paddleocr import PaddleOCR
except ImportError:
    with open("/tmp/ocr_response.json", "w") as f:
        json.dump({"status": "error", "message": "PaddleOCR not installed. Run: pip3 install paddlepaddle paddleocr"}, f)
    sys.exit(1)

# Load models
ocr = PaddleOCR(
    text_detection_model_name="PP-OCRv5_mobile_det",
    text_recognition_model_name="PP-OCRv5_mobile_rec",
    use_doc_orientation_classify=False,
    use_doc_unwarping=False,
    use_textline_orientation=False,
)

# Signal ready
with open("/tmp/ocr_ready", "w") as f:
    f.write("ready")

REQ_FILE = "/tmp/ocr_request.txt"
RESP_FILE = "/tmp/ocr_response.json"

last_size = 0

while True:
    try:
        if not os.path.exists(REQ_FILE):
            time.sleep(0.2)
            continue

        stat = os.stat(REQ_FILE)
        if stat.st_size == last_size:
            time.sleep(0.2)
            continue

        with open(REQ_FILE, "r") as f:
            lines = f.readlines()
        last_size = stat.st_size

        # Process the last line
        line = lines[-1].strip() if lines else ""
        if not line:
            continue
        if line == "exit":
            break
        if not os.path.exists(line):
            resp = {"status": "error", "message": f"File not found: {line}"}
        else:
            try:
                result = ocr.predict(line)
                items = []
                for res in result:
                    rec_texts = res.get("rec_texts", [])
                    rec_scores = res.get("rec_scores", [])
                    dt_polys = res.get("dt_polys", [])
                    for i, (text, score) in enumerate(zip(rec_texts, rec_scores)):
                        poly = dt_polys[i] if i < len(dt_polys) else [[0,0]]*4
                        items.append({
                            "text": text, "confidence": float(score),
                            "bbox": {"x": float(poly[0][0]), "y": float(poly[0][1]),
                                     "w": float(poly[2][0]-poly[0][0]) if len(poly)>=3 else 0,
                                     "h": float(poly[2][1]-poly[0][1]) if len(poly)>=3 else 0}
                        })
                resp = {"status": "ok", "results": items}
            except Exception as e:
                resp = {"status": "error", "message": str(e)}

        with open(RESP_FILE, "w") as f:
            json.dump(resp, f)

    except KeyboardInterrupt:
        break
    except Exception:
        time.sleep(0.5)
