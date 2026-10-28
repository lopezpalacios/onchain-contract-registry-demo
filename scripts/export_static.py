#!/usr/bin/env python3
"""Export the current SQLite registry into a browser-only data bundle.

Runtime uses only HTML/CSS/JS. This script is a build-time helper.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

from app import (  # noqa: E402
    DB_PATH,
    RegistryDB,
    approvals,
    controls,
    council,
    discovery,
    instance_detail,
    inventory,
    reference,
    registrations,
    summary,
    template_detail,
    template_meta,
    templates,
)


def main() -> None:
    conn = RegistryDB(DB_PATH).connect()
    try:
        contract_ids = [r["id"] for r in conn.execute("SELECT id FROM contract_instance ORDER BY id").fetchall()]
        template_ids = [r["id"] for r in conn.execute("SELECT id FROM template ORDER BY id").fetchall()]
        data = {
            "version": "static-" + datetime.now(timezone.utc).strftime("%Y-%m-%d-%H%M"),
            "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "summary": summary(conn),
            "contracts": {"items": inventory(conn, {})},
            "contractDetails": {cid: instance_detail(conn, cid) for cid in contract_ids},
            "templates": {"items": templates(conn), "meta": template_meta(conn)},
            "templateDetails": {tid: template_detail(conn, tid) for tid in template_ids},
            "approvals": approvals(conn),
            "registrations": registrations(conn),
            "discovery": discovery(conn),
            "controls": controls(conn),
            "council": council(conn),
            "reference": reference(conn),
        }
    finally:
        conn.close()
    output = ROOT / "web" / "data.js"
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"), default=str).replace("</", "<\\/")
    output.write_text("window.REGISTRY_DATA = " + payload + ";\n", encoding="utf-8")
    print(f"wrote {output} ({output.stat().st_size / 1024:.0f} KiB)")


if __name__ == "__main__":
    main()
