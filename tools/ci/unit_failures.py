#!/usr/bin/env python3
"""Print the failures from the latest gdUnit4 report (reports/report_1/results.xml)."""
import re
import sys
from pathlib import Path

report = Path(__file__).resolve().parents[2] / "reports" / "report_1" / "results.xml"
if not report.exists():
    sys.exit(f"no report at {report}")
text = report.read_text(encoding="utf-8")
failures = re.findall(r'<failure message="([^"]+)"[^>]*>\s*<!\[CDATA\[(.*?)\]\]>', text, re.S)
for message, body in failures:
    print(message)
    print(re.sub(r"\x1b\[[0-9;]*m", "", body).strip())
    print()
print(f"{len(failures)} failure(s)")
