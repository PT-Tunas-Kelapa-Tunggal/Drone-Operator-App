#!/usr/bin/env python3
"""Check an exported CKDB schema against the evaluated Swift record-key contract.

This offline check validates declaration structure and field presence. CloudKit's
import step remains responsible for validating field types, indexes, and permissions.
"""

from __future__ import annotations

import argparse
import json
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
    """Parse record/role declarations without treating comments or grants as fields."""

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

    def grant(self) -> None:
        self.expect("GRANT")
        self.name()
        while self.peek() == ",":
            self.take()
            self.name()
        self.expect("TO")
        self.name()

    def parse(self) -> dict[str, dict[str, str]]:
        self.expect("DEFINE")
        self.expect("SCHEMA")
        records = {}
        roles = set()
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
                self.expect("(")
                fields = {}
                while self.peek() != ")":
                    if self.peek() == "GRANT":
                        self.grant()
                    else:
                        field = self.name()
                        if field in fields:
                            raise SchemaError(f"Duplicate field {record}.{field}")
                        fields[field] = self.field_type()
                        while IDENTIFIER.fullmatch(self.peek()):
                            self.take()  # Index/field modifiers are checked by CloudKit during import.
                    if self.peek() != ")":
                        self.expect(",")
                self.expect(")")
                records[record] = fields
            self.expect(";")
        if not records:
            raise SchemaError("Schema has no record types")
        return records


def load_contract(record_keys: Path) -> dict:
    """Evaluate the real allKeys sets, including aliases and shared metadata keys."""
    with tempfile.TemporaryDirectory(prefix="cloudkit-schema-check-") as directory:
        temp = Path(directory)
        main = temp / "main.swift"
        main.write_text('''import Foundation
let contract: [String: Any] = [
    "recordType": RecordKeys.recordType,
    "fields": Array(RecordKeys.iOSOwned.allKeys.union(RecordKeys.MacOSOwned.allKeys)).sorted(),
]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: contract))
''')
        binary = temp / "record-keys"
        compiled = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(temp / "module-cache"),
             str(record_keys), str(main), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compiled.returncode:
            raise SchemaError(f"Could not evaluate {record_keys}:\n{compiled.stderr.strip()}")
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise SchemaError(f"Could not read record-key contract:\n{result.stderr.strip()}")
        contract = json.loads(result.stdout)
        if not contract.get("recordType") or not contract.get("fields"):
            raise SchemaError("Record-key contract must define a record type and field keys")
        return contract


def validate_contract(records: dict[str, dict[str, str]], contract: dict) -> None:
    record = contract["recordType"]
    if record not in records:
        raise SchemaError(f"Missing contract RECORD TYPE {record}")
    missing = sorted(set(contract["fields"]) - records[record].keys())
    if missing:
        raise SchemaError(
            f"RECORD TYPE {record} is missing contract fields: {', '.join(missing)}.\n"
            "Add the fields to the schema, or update the shared contract if they were intentionally removed."
        )


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, default=repo / "Config/CloudKit/schema.ckdb")
    parser.add_argument("--record-keys", type=Path,
                        default=repo / "ControlDroneMapping/CloudKitContract/Core/RecordKeys.swift")
    args = parser.parse_args()
    try:
        records = SchemaParser(args.schema.read_text()).parse()
        contract = load_contract(args.record_keys)
        validate_contract(records, contract)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"error: CloudKit schema check failed: {error}", file=sys.stderr)
        return 1
    print(f"CloudKit schema parsed ({len(records)} record types); "
          f"all {len(contract['fields'])} contract fields exist in {contract['recordType']}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
