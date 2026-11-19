"""Regression coverage for stale exports, Swift aliases, and schema declaration scope."""

from pathlib import Path
import re
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

from check_cloudkit_schema import SchemaError, SchemaParser, load_contract, validate_contract


class CloudKitSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        repo = SCRIPTS.parent
        cls.contract = load_contract(repo / "ControlDroneMapping/CloudKitContract/Core/RecordKeys.swift")
        cls.schema = (repo / "Config/CloudKit/schema.ckdb").read_text()

    def test_committed_schema_supports_current_contract(self):
        validate_contract(SchemaParser(self.schema).parse(), self.contract)

    def test_comments_and_other_record_types_cannot_hide_a_missing_field(self):
        schema = re.sub(r"^\s*farmBoundary\s+LIST<LOCATION>[^\n]*", "", self.schema, flags=re.MULTILINE)
        schema += '''
// farmBoundary LIST<LOCATION>,
/* RECORD TYPE PlantationScanRequest (farmBoundary LIST<LOCATION>); */
RECORD TYPE Unrelated (
    farmBoundary LIST<LOCATION>,
    GRANT READ TO "a role mentioning farmBoundary"
);
'''
        with self.assertRaisesRegex(SchemaError, "missing contract fields: farmBoundary"):
            validate_contract(SchemaParser(schema).parse(), self.contract)

    def test_missing_optional_writer_field_is_reported(self):
        schema = re.sub(r"^\s*plannedOperatorVisitDate\s+TIMESTAMP[^\n]*", "", self.schema, flags=re.MULTILINE)
        with self.assertRaisesRegex(SchemaError, "plannedOperatorVisitDate"):
            validate_contract(SchemaParser(schema).parse(), self.contract)

    def test_extra_legacy_fields_are_allowed(self):
        schema = self.schema.replace("RECORD TYPE PlantationScanRequest (", "RECORD TYPE PlantationScanRequest (legacyField STRING,")
        validate_contract(SchemaParser(schema).parse(), self.contract)

    def test_missing_record_type_is_reported(self):
        with self.assertRaisesRegex(SchemaError, "Missing contract RECORD TYPE PlantationScanRequest"):
            validate_contract(SchemaParser("DEFINE SCHEMA RECORD TYPE Other (value STRING);").parse(), self.contract)

    def test_comments_formatting_lists_and_grant_commas(self):
        records = SchemaParser('''DEFINE /* comment */ SCHEMA
CREATE ROLE "Reviewer // (team)";
RECORD TYPE "Request" (
    "boundary" LIST<LOCATION> QUERYABLE, title STRING,
    GRANT READ, WRITE TO "Reviewer // (team)",
    GRANT CREATE TO "_icloud"
);''').parse()
        self.assertEqual(records, {"Request": {"boundary": "LIST<LOCATION>", "title": "STRING"}})

    def test_empty_malformed_and_duplicate_declarations_fail(self):
        for schema in (
            "",
            "DEFINE SCHEMA",
            "DEFINE SCHEMA // RECORD TYPE Request (value STRING);",
            "DEFINE SCHEMA RECORD TYPE Request (value STRING)",
            "DEFINE SCHEMA RECORD TYPE Request (value STRING;",
            "DEFINE SCHEMA RECORD TYPE Request (value STRING); garbage",
            "DEFINE SCHEMA RECORD TYPE Request (value STRING, value INT64);",
            "DEFINE SCHEMA RECORD TYPE Request (); RECORD TYPE Request ();",
            "DEFINE SCHEMA /* unterminated comment",
        ):
            with self.subTest(schema=schema), self.assertRaises(SchemaError):
                SchemaParser(schema).parse()

    def test_contract_is_evaluated_instead_of_scraping_swift_strings(self):
        with tempfile.TemporaryDirectory(prefix="cloudkit-contract-test-") as directory:
            path = Path(directory) / "RecordKeys.swift"
            path.write_text('''public enum RecordKeys {
    public static let recordType = "Request" + "V2"
    public static let schemaVersion = "contract_version"
    // public static let obsolete = "unused_old_key"
    public static let unrelatedDocumentation = "not_a_field"
    public enum iOSOwned {
        public static let displayName = "serialized_farmer_name"
        public static let allKeys: Set<String> = [displayName, RecordKeys.schemaVersion]
    }
    public enum MacOSOwned {
        public static let allKeys: Set<String> = ["visit_at", RecordKeys.schemaVersion]
    }
}''')
            contract = load_contract(path)
        self.assertEqual(contract["recordType"], "RequestV2")
        self.assertEqual(contract["fields"], ["contract_version", "serialized_farmer_name", "visit_at"])
        validate_contract(SchemaParser('''DEFINE SCHEMA RECORD TYPE RequestV2 (
            contract_version INT64, serialized_farmer_name STRING, visit_at TIMESTAMP
        );''').parse(), contract)


if __name__ == "__main__":
    unittest.main()
