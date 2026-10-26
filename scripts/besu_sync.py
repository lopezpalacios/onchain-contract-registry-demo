#!/usr/bin/env python3
"""Besu / EVM JSON-RPC discovery adapter for the contract registry.

What it does
------------
- Walks blocks (checkpointed or a single range) and finds contract-creation txs.
- Reads the deployed runtime code and fingerprints it.
- Detects EIP-1167 clones and EIP-1967 proxies (implementation / beacon / admin).
- Matches known template runtime or init-code hashes.
- Writes unknown or unlinked contracts to ``discovery_queue``.
- Records an auditable ``sync_run`` with block range and counters.

It deliberately does NOT auto-approve or auto-create business ownership. A
matched contract is still a triage item until an operator links it and the
deployment evidence is verified. That is the control that prevents shadow
deployments from becoming "official" by accident.

Examples
--------
    python3 scripts/besu_sync.py --mock --chain ch-besu-prod
    python3 scripts/besu_sync.py --rpc https://besu:8545 --chain ch-besu-prod \
        --from-block 1844300 --to-block 1844400
    python3 scripts/besu_sync.py --inspect 0x46009f... --chain ch-besu-prod --rpc ...
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "registry"))
from keccak import address_from_label, eip55, keccak256, selector  # noqa: E402

DEFAULT_DB = ROOT / "data" / "registry.db"

EIP1967_IMPLEMENTATION = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
EIP1967_BEACON = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
EIP1967_ADMIN = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
EIP1167_PREFIX = "363d3d373d3d3d363d73"
BEACON_IMPLEMENTATION_SELECTOR = selector("implementation()")


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def rpc(url: str, method: str, params: list | None = None, timeout: int = 20):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or []}).encode()
    request = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode())
    except urllib.error.URLError as exc:
        raise RuntimeError(f"RPC {method} failed: {exc}") from exc
    if "error" in body:
        raise RuntimeError(f"RPC {method} error: {body['error']}")
    return body.get("result")


def hex_block(value: int) -> str:
    return hex(value)


def as_int(value) -> int:
    if value is None:
        return 0
    return int(value, 16) if isinstance(value, str) else int(value)


def address_from_slot(value: str | None) -> str | None:
    if not value or value in ("0x", "0x0"):
        return None
    raw = value.removeprefix("0x")
    if len(raw) < 40:
        return None
    address = "0x" + raw[-40:]
    if address == "0x" + "0" * 40:
        return None
    return address.lower()


def normalise_code(code: str) -> str:
    code = (code or "0x").lower()
    if code.startswith("0x"):
        code = code[2:]
    return code


def proxy_info(rpc_url: str, address: str, code: str) -> dict:
    code_hex = normalise_code(code)
    if code_hex.startswith(EIP1167_PREFIX):
        implementation = "0x" + code_hex[len(EIP1167_PREFIX):len(EIP1167_PREFIX) + 40]
        return {"proxy_type": "eip1167-clone", "implementation": implementation, "beacon": None, "admin": None}
    try:
        implementation = address_from_slot(rpc(rpc_url, "eth_getStorageAt", [address, EIP1967_IMPLEMENTATION, "latest"]))
        beacon = address_from_slot(rpc(rpc_url, "eth_getStorageAt", [address, EIP1967_BEACON, "latest"]))
        admin = address_from_slot(rpc(rpc_url, "eth_getStorageAt", [address, EIP1967_ADMIN, "latest"]))
    except RuntimeError:
        return {"proxy_type": "none", "implementation": None, "beacon": None, "admin": None}
    if beacon:
        try:
            result = rpc(rpc_url, "eth_call", [{"to": beacon, "data": BEACON_IMPLEMENTATION_SELECTOR}, "latest"])
            implementation = address_from_slot(result)
        except RuntimeError:
            implementation = None
        return {"proxy_type": "beacon", "implementation": implementation, "beacon": beacon, "admin": admin}
    if implementation:
        return {"proxy_type": "eip1967-uups", "implementation": implementation, "beacon": None, "admin": admin}
    return {"proxy_type": "none", "implementation": None, "beacon": None, "admin": admin}


def match_template(conn: sqlite3.Connection, runtime_hash: str, init_hash: str | None, proxy: dict, rpc_url: str | None = None):
    exact = conn.execute(
        "SELECT id, name, version, default_risk_tier FROM template WHERE lower(runtime_code_hash) = ? LIMIT 1",
        (runtime_hash.lower(),),
    ).fetchone()
    if exact:
        return dict(exact), "runtime-hash"
    if init_hash:
        by_init = conn.execute(
            "SELECT id, name, version, default_risk_tier FROM template WHERE lower(initcode_hash) = ? LIMIT 1",
            (init_hash.lower(),),
        ).fetchone()
        if by_init:
            return dict(by_init), "initcode-hash"
    # For a proxy, the interesting template is the implementation, not the proxy shell.
    if proxy.get("implementation") and rpc_url:
        try:
            impl_code = rpc(rpc_url, "eth_getCode", [proxy["implementation"], "latest"])
            impl_hash = "0x" + keccak256(bytes.fromhex(normalise_code(impl_code)))
            by_impl = conn.execute(
                "SELECT id, name, version, default_risk_tier FROM template WHERE lower(runtime_code_hash) = ? LIMIT 1",
                (impl_hash,),
            ).fetchone()
            if by_impl:
                return dict(by_impl), "proxy-implementation"
        except (RuntimeError, ValueError):
            pass
    return None, None


def upsert_discovery(conn, *, chain_id, address, runtime_hash, tx_hash, deployer, block_number,
                     suspected_template_id, classification, risk_hint, notes, dry_run=False):
    existing = conn.execute(
        "SELECT id FROM discovery_queue WHERE chain_id = ? AND address = ?",
        (chain_id, address),
    ).fetchone()
    if dry_run:
        return "existing" if existing else "would-create"
    if existing:
        conn.execute(
            """
            UPDATE discovery_queue
            SET runtime_code_hash = ?, tx_hash = ?, deployer_address = ?, block_number = ?,
                first_seen_at = ?, suspected_template_id = ?, classification = ?, risk_hint = ?,
                notes = ?, status = CASE WHEN status = 'linked' THEN status ELSE 'triage' END
            WHERE id = ?
            """,
            (runtime_hash, tx_hash, deployer, block_number, now(), suspected_template_id,
             classification, risk_hint, notes, existing["id"]),
        )
        return existing["id"]
    discovery_id = "disc-" + keccak256(f"{chain_id}:{address}")[:12]
    conn.execute(
        """
        INSERT INTO discovery_queue
          (id, chain_id, address, runtime_code_hash, tx_hash, deployer_address, block_number,
           first_seen_at, status, suspected_template_id, classification, risk_hint, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, ?)
        """,
        (discovery_id, chain_id, address, runtime_hash, tx_hash, deployer, block_number,
         now(), suspected_template_id, classification, risk_hint, notes),
    )
    return discovery_id


def process_creation(conn, rpc_url: str, chain_id: str, block: dict, tx: dict, dry_run=False):
    receipt = rpc(rpc_url, "eth_getTransactionReceipt", [tx["hash"]])
    if not receipt or as_int(receipt.get("status")) != 1:
        return None
    address = (receipt.get("contractAddress") or "").lower()
    if not address:
        return None
    code = rpc(rpc_url, "eth_getCode", [address, "latest"])
    if not code or code in ("0x", "0x0"):
        return None
    runtime_hash = "0x" + keccak256(bytes.fromhex(normalise_code(code)))
    init_hash = "0x" + keccak256(bytes.fromhex(normalise_code(tx.get("input", "0x")))) if tx.get("input") else None
    proxy = proxy_info(rpc_url, address, code)
    template, how = match_template(conn, runtime_hash, init_hash, proxy, rpc_url)
    if template:
        classification = f"Matched {template['name']} v{template['version']} via {how}"
        risk_hint = template["default_risk_tier"]
        notes = "Template match found. Confirm deployment request, manifest and approvals before linking."
        status = "triage"
    else:
        classification = "No approved template match"
        risk_hint = "high"
        notes = "No matching template hash, init-code hash or proxy implementation. Triage as a potential shadow deployment."
        status = "new"
    discovery_id = upsert_discovery(
        conn,
        chain_id=chain_id,
        address=address,
        runtime_hash=runtime_hash,
        tx_hash=tx["hash"],
        deployer=(tx.get("from") or "").lower(),
        block_number=as_int(block.get("number")),
        suspected_template_id=template["id"] if template else None,
        classification=classification,
        risk_hint=risk_hint,
        notes=notes,
        dry_run=dry_run,
    )
    if not dry_run:
        conn.execute(
            "UPDATE discovery_queue SET status = ? WHERE id = ? AND status NOT IN ('linked', 'ignored')",
            (status, discovery_id),
        )
    return {
        "address": address,
        "tx_hash": tx["hash"],
        "runtime_code_hash": runtime_hash,
        "template_id": template["id"] if template else None,
        "status": status,
        "discovery_id": discovery_id,
    }


def run_range(conn, rpc_url: str, chain: dict, from_block: int, to_block: int, dry_run=False):
    run_id = "sr-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    if not dry_run:
        conn.execute(
            """
            INSERT INTO sync_run (id, chain_id, mode, from_block, to_block, status, started_at)
            VALUES (?, ?, 'backfill', ?, ?, 'running', ?)
            """,
            (run_id, chain["id"], from_block, to_block, now()),
        )
        conn.commit()
    found = matched = unknown = errors = txs = 0
    try:
        for number in range(from_block, to_block + 1):
            block = rpc(rpc_url, "eth_getBlockByNumber", [hex_block(number), True])
            if not block:
                continue
            for tx in block.get("transactions", []):
                txs += 1
                if tx.get("to") is not None:
                    continue
                try:
                    result = process_creation(conn, rpc_url, chain["id"], block, tx, dry_run=dry_run)
                    if result:
                        found += 1
                        if result["template_id"]:
                            matched += 1
                        else:
                            unknown += 1
                except Exception as exc:  # keep the run going; record the count
                    errors += 1
                    print(f"  ! {tx.get('hash')}: {exc}", file=sys.stderr)
            if not dry_run and number % 50 == 0:
                conn.commit()
        if not dry_run:
            conn.execute(
                """
                UPDATE sync_run
                SET blocks_scanned = ?, txs_scanned = ?, contracts_found = ?,
                    contracts_matched = ?, unknown = ?, errors = ?, status = ?,
                    finished_at = ?, checkpoint_block = ?
                WHERE id = ?
                """,
                (to_block - from_block + 1, txs, found, matched, unknown, errors,
                 "success" if errors == 0 else "partial", now(), to_block, run_id),
            )
            conn.commit()
    except Exception as exc:
        if not dry_run:
            conn.execute(
                """
                UPDATE sync_run SET status='failed', finished_at=?, error_text=?,
                    blocks_scanned=?, txs_scanned=?, contracts_found=?, contracts_matched=?, unknown=?, errors=?
                WHERE id=?
                """,
                (now(), str(exc), to_block - from_block + 1, txs, found, matched, unknown, errors, run_id),
            )
            conn.commit()
        raise
    return {"run_id": run_id, "found": found, "matched": matched, "unknown": unknown, "errors": errors, "txs": txs}


def run_mock(db_path: Path, chain_id: str = "ch-besu-prod") -> dict:
    """Deterministic no-node sync used by the UI demo button."""
    conn = connect(db_path)
    try:
        chain = conn.execute("SELECT * FROM chain WHERE id = ?", (chain_id,)).fetchone()
        if chain is None:
            raise RuntimeError(f"unknown chain: {chain_id}")
        run_id = "sr-mock-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        address = address_from_label("demo-sync-unknown-contract")
        runtime_hash = "0x" + keccak256("demo-sync-runtime-code")
        tx_hash = "0x" + keccak256("demo-sync-deployment-tx")
        conn.execute(
            """
            INSERT INTO sync_run (id, chain_id, mode, from_block, to_block, blocks_scanned,
                                  txs_scanned, contracts_found, contracts_matched, unknown, errors,
                                  status, started_at, finished_at, checkpoint_block)
            VALUES (?, ?, 'mock', 1844400, 1844401, 2, 47, 1, 0, 1, 0, 'success', ?, ?, 1844401)
            """,
            (run_id, chain_id, now(), now()),
        )
        conn.execute(
            """
            INSERT INTO discovery_queue
              (id, chain_id, address, runtime_code_hash, tx_hash, deployer_address, block_number,
               first_seen_at, status, suspected_template_id, classification, risk_hint, notes)
            VALUES ('disc-mock', ?, ?, ?, ?, '0x8e21784f4a55d8cf2c21db7511499874ea54905e', 1844401,
                    ?, 'new', NULL, 'Mock discovery: ERC-20-like selectors, no template match', 'high',
                    'Generated by the demo sync button. It is intentionally unregistered to exercise the reconciliation queue.')
            ON CONFLICT(chain_id, address) DO UPDATE SET
                first_seen_at = excluded.first_seen_at,
                runtime_code_hash = excluded.runtime_code_hash,
                tx_hash = excluded.tx_hash,
                status = 'new',
                notes = excluded.notes
            """,
            (chain_id, address, runtime_hash, tx_hash, now()),
        )
        conn.commit()
        return {"ok": True, "run_id": run_id, "discovered": 1, "matched": 0, "unknown": 1, "address": address}
    finally:
        conn.close()


def inspect(db_path: Path, rpc_url: str, chain_id: str, address: str) -> dict:
    conn = connect(db_path)
    try:
        chain = conn.execute("SELECT * FROM chain WHERE id = ?", (chain_id,)).fetchone()
        if chain is None:
            raise RuntimeError(f"unknown chain: {chain_id}")
        code = rpc(rpc_url, "eth_getCode", [address, "latest"])
        if not code or code in ("0x", "0x0"):
            raise RuntimeError("no code at address")
        runtime_hash = "0x" + keccak256(bytes.fromhex(normalise_code(code)))
        proxy = proxy_info(rpc_url, address, code)
        template, how = match_template(conn, runtime_hash, None, proxy, rpc_url)
        return {
            "address": address,
            "checksum": eip55(address),
            "runtime_code_hash": runtime_hash,
            "proxy": proxy,
            "template": template,
            "match": how,
        }
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--chain", default="ch-besu-prod", help="Registry chain id")
    parser.add_argument("--rpc", default=None, help="JSON-RPC endpoint, e.g. https://besu:8545")
    parser.add_argument("--from-block", type=int, default=None)
    parser.add_argument("--to-block", type=int, default=None)
    parser.add_argument("--mock", action="store_true", help="Insert a deterministic demo discovery")
    parser.add_argument("--inspect", metavar="ADDRESS", help="Inspect one address without writing")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--poll", type=float, default=0, help="Poll every N seconds (0 = run once)")
    args = parser.parse_args()

    if args.mock:
        result = run_mock(args.db, args.chain)
        print(json.dumps(result, indent=2))
        return 0
    if args.inspect:
        if not args.rpc:
            parser.error("--inspect requires --rpc")
        print(json.dumps(inspect(args.db, args.rpc, args.chain, args.inspect), indent=2))
        return 0
    if not args.rpc:
        parser.error("--rpc is required unless --mock or --inspect is used")

    conn = connect(args.db)
    try:
        chain = conn.execute("SELECT * FROM chain WHERE id = ?", (args.chain,)).fetchone()
        if chain is None:
            parser.error(f"unknown chain: {args.chain}")
        remote_chain_id = as_int(rpc(args.rpc, "eth_chainId"))
        if remote_chain_id != chain["chain_id"]:
            raise SystemExit(f"chain mismatch: RPC {remote_chain_id} vs registry {chain['chain_id']}")
        while True:
            latest = as_int(rpc(args.rpc, "eth_blockNumber"))
            start = args.from_block if args.from_block is not None else max(0, latest - 100)
            end = args.to_block if args.to_block is not None else latest
            result = run_range(conn, args.rpc, dict(chain), start, end, dry_run=args.dry_run)
            print(json.dumps(result, indent=2))
            if not args.poll:
                break
            time.sleep(args.poll)
            args.from_block = end + 1
            args.to_block = None
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
