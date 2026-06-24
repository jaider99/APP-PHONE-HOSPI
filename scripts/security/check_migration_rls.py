#!/usr/bin/env python3
"""Fail CI when tenant tables lack migration-level RLS hardening.

This static lint is intentionally conservative. It looks for public tables
created with a company_id column, then verifies the migration set contains
ENABLE ROW LEVEL SECURITY, FORCE ROW LEVEL SECURITY, and at least one policy
for each table.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"


def normalize_sql(sql: str) -> str:
    return re.sub(r"\s+", " ", sql.lower())


def created_tenant_tables(sql: str) -> set[str]:
    tables: set[str] = set()
    pattern = re.compile(
        r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?(?P<table>[a-z_][a-z0-9_]*)\s*\((?P<body>.*?)\);",
        re.IGNORECASE | re.DOTALL,
    )

    for match in pattern.finditer(sql):
        body = match.group("body")
        if re.search(r"\bcompany_id\b", body, re.IGNORECASE):
            tables.add(match.group("table").lower())

    return tables


def has_statement(sql: str, table: str, action: str) -> bool:
    table_pattern = rf"(?:public\.)?{re.escape(table)}"
    return re.search(
        rf"alter\s+table\s+{table_pattern}\s+{action}\s+row\s+level\s+security",
        sql,
        re.IGNORECASE,
    ) is not None


def has_policy(sql: str, table: str) -> bool:
    table_pattern = rf"(?:public\.)?{re.escape(table)}"
    return re.search(
        rf"create\s+policy\s+[^;]+\s+on\s+{table_pattern}\b",
        sql,
        re.IGNORECASE | re.DOTALL,
    ) is not None


def main() -> int:
    migration_files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not migration_files:
        print("No migration files found.", file=sys.stderr)
        return 1

    combined_sql = "\n".join(path.read_text(encoding="utf-8") for path in migration_files)
    normalized_sql = normalize_sql(combined_sql)
    tenant_tables = created_tenant_tables(combined_sql)

    failures: list[str] = []
    for table in sorted(tenant_tables):
        if not has_statement(normalized_sql, table, "enable"):
            failures.append(f"{table}: missing ENABLE ROW LEVEL SECURITY")
        if not has_statement(normalized_sql, table, "force"):
            failures.append(f"{table}: missing FORCE ROW LEVEL SECURITY")
        if not has_policy(normalized_sql, table):
            failures.append(f"{table}: missing CREATE POLICY")

    if failures:
        print("Tenant-table RLS lint failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Tenant-table RLS lint passed for {len(tenant_tables)} table(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())