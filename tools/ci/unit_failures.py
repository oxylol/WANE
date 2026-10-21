#!/usr/bin/env python3
"""Print the failures from the latest gdUnit4 reports (reports/unit/<process>/report_N/results.xml;
the unit stage runs one gdUnit4 process per share of the suites, so there is a report for each)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

reports = Path(__file__).resolve().parents[2] / "reports" / "unit"


def newest(process_dir: Path) -> Path | None:
    """The results.xml of the highest-numbered report_N folder in `process_dir`."""
    found = [
        (int(p.parent.name.removeprefix("report_")), p)
        for p in process_dir.glob("report_*/results.xml")
        if p.parent.name.removeprefix("report_").isdigit()
    ]
    return max(found)[1] if found else None


results = [r for r in (newest(d) for d in sorted(reports.glob("*")) if d.is_dir()) if r]
if not results:
    sys.exit(f"no report under {reports}")
count = 0
for report in results:
    text = report.read_text(encoding="utf-8")
    failures = re.findall(r'<failure message="([^"]+)"[^>]*>\s*<!\[CDATA\[(.*?)\]\]>', text, re.S)
    for message, body in failures:
        print(message)
        print(re.sub(r"\x1b\[[0-9;]*m", "", body).strip())
        print()
    count += len(failures)
print(f"{count} failure(s) in {len(results)} report(s)")
