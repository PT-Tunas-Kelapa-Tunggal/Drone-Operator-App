#!/usr/bin/env python3
"""Compare a live CloudKit schema with a checked-in snapshot."""

from __future__ import annotations

import argparse
from difflib import unified_diff
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


class SchemaError(ValueError):
    pass


TOKEN = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9]*|[(),;<>]', re.DOTALL)
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*\Z")


def tokenize(text: str) -> list[str]:
    tokens = []
    position = 0
    while position < len(text):
        match = TOKEN.match(text, position)
        if not match:
            line = text.count("\n", 0, position) + 1
            raise SchemaError(f"Unexpected schema syntax at line {line}: {text[position:position + 30]!r}")
        token = match.group()
        if not token.isspace() and not token.startswith(("//", "/*")):
            tokens.append(token)
        position = match.end()
    return tokens


class SchemaParser:
    """Parse exported CloudKit declarations while retaining indexes and permissions."""

    def __init__(self, text: str):
        self.tokens = tokenize(text)
        self.position = 0

    def peek(self) -> str:
        return self.tokens[self.position] if self.position < len(self.tokens) else "<end of file>"

    def take(self) -> str:
        token = self.peek()
        if token == "<end of file>":
            raise SchemaError("Unexpected end of schema")
        self.position += 1
        return token

    def expect(self, expected: str) -> None:
        actual = self.take()
        if actual != expected:
            raise SchemaError(f"Expected {expected!r}, found {actual!r}")

    def name(self) -> str:
        token = self.take()
        if token.startswith('"'):
            return json.loads(token)
        if not IDENTIFIER.fullmatch(token):
            raise SchemaError(f"Expected a name, found {token!r}")
        return token

    def field_type(self) -> str:
        name = self.take()
        if not IDENTIFIER.fullmatch(name):
            raise SchemaError(f"Expected a field type, found {name!r}")
        if self.peek() == "<":
            self.take()
            name += "<" + self.field_type() + ">"
            self.expect(">")
        return name

    def grant(self) -> tuple[str, set[str]]:
        self.expect("GRANT")
        rights = {self.name()}
        while self.peek() == ",":
            self.take()
            rights.add(self.name())
        self.expect("TO")
        return self.name(), rights

    def record_body(self) -> list[str]:
        self.expect("(")
        fields: dict[str, str] = {}
        grants: dict[str, set[str]] = {}
        while self.peek() != ")":
            if self.peek() == "GRANT":
                role, rights = self.grant()
                grants.setdefault(role, set()).update(rights)
            else:
                field = self.name()
                if field in fields:
                    raise SchemaError(f"Duplicate field {field!r}")
                field_type = self.field_type()
                indexes: set[str] = set()
                while IDENTIFIER.fullmatch(self.peek()):
                    index = self.take()
                    if index in indexes:
                        raise SchemaError(f"Duplicate modifier {index} on {field!r}")
                    indexes.add(index)
                fields[field] = " ".join((field_type, *sorted(indexes)))
            if self.peek() != ")":
                self.expect(",")
        self.expect(")")
        definitions = [f"    {json.dumps(field)} {definition}," for field, definition in sorted(fields.items())]
        permissions = [f"    GRANT {', '.join(sorted(rights))} TO {json.dumps(role)},"
                       for role, rights in sorted(grants.items())]
        return definitions + permissions

    def parse(self) -> list[str]:
        self.expect("DEFINE")
        self.expect("SCHEMA")
        records: dict[str, list[str]] = {}
        roles: set[str] = set()
        while self.position < len(self.tokens):
            if self.peek() == "CREATE":
                self.take()
                self.expect("ROLE")
                role = self.name()
                if role in roles:
                    raise SchemaError(f"Duplicate role {role!r}")
                roles.add(role)
            else:
                self.expect("RECORD")
                self.expect("TYPE")
                record = self.name()
                if record in records:
                    raise SchemaError(f"Duplicate RECORD TYPE {record}")
                records[record] = self.record_body()
            self.expect(";")
        if not records:
            raise SchemaError("Schema has no record types")

        lines = [f"CREATE ROLE {json.dumps(role)};" for role in sorted(roles)]
        for record, body in sorted(records.items()):
            lines.extend((f"RECORD TYPE {json.dumps(record)} (", *body, ");"))
        return lines


def compare_schemas(expected: list[str], actual: list[str], target: str) -> None:
    diff = "\n".join(unified_diff(
        expected, actual,
        fromfile="CloudKitContract/schema.ckdb", tofile=f"live {target}", lineterm="",
    ))
    if diff:
        raise SchemaError(
            f"Schema drift for {target}:\n{diff}\n"
            "In CloudKit Console, review the difference. If the live schema is correct, "
            "export it and update the branch snapshot in both repos. If a release partition "
            "is behind, manually promote the reviewed schema in that container and rerun CI."
        )


def export_live_schema(team_id: str, container: str, partition: str) -> list[str]:
    target = f"{container} ({partition})"
    token = os.environ.get("CLOUDKIT_MANAGEMENT_TOKEN")
    if not token:
        raise SchemaError(f"Cannot export {target}: CLOUDKIT_MANAGEMENT_TOKEN is missing")
    with tempfile.TemporaryDirectory(prefix="cloudkit-live-") as directory:
        output = Path(directory) / "schema.ckdb"
        try:
            result = subprocess.run(
                ["xcrun", "cktool", "export-schema", "--token", token, "--team-id", team_id,
                 "--container-id", container, "--environment", partition, "--output-file", str(output)],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
            )
        except subprocess.TimeoutExpired:
            raise SchemaError(f"CloudKit export timed out for {target}") from None
        except OSError as error:
            raise SchemaError(f"Cannot run cktool for {target}: {error}") from None
        if result.returncode:
            details = (result.stderr.strip() or result.stdout.strip()).replace(token, "[redacted]")
            raise SchemaError(f"CloudKit export failed for {target}: {details or result.returncode}")
        try:
            return SchemaParser(output.read_text(encoding="utf-8")).parse()
        except (ValueError, OSError) as error:
            raise SchemaError(f"Cannot read CloudKit export for {target}: {error}") from None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--container", required=True)
    parser.add_argument("--partition", choices=("development", "production"), required=True)
    args = parser.parse_args()
    try:
        expected = SchemaParser(args.schema.read_text(encoding="utf-8")).parse()
        actual = export_live_schema(args.team_id, args.container, args.partition)
        target = f"{args.container} ({args.partition})"
        compare_schemas(expected, actual, target)
        print(f"CloudKit schema matches {target}.")
    except (OSError, ValueError) as error:
        print(f"error: CloudKit schema check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
