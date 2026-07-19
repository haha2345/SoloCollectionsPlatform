from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TYPES_PATH = ROOT / "src" / "SoloCollectionsTypes.h"


class StableDomainTypeContractTests(unittest.TestCase):
    def test_stable_ids_use_explicit_unsigned_storage(self):
        text = TYPES_PATH.read_text(encoding="utf-8")
        expected = {
            "CollectionTypeId": "std::uint16_t",
            "CollectionId": "std::uint32_t",
            "LogicalClassId": "std::uint16_t",
            "LogicalRaceId": "std::uint16_t",
            "CollectionRevision": "std::uint64_t",
        }
        for type_name, storage in expected.items():
            self.assertRegex(
                text,
                rf"using\s+{type_name}\s*=\s*StableId<[^,>]+,\s*{re.escape(storage)}\s*>",
            )
        self.assertIn("explicit constexpr StableId(Storage value)", text)
        self.assertNotIn("using CollectionTypeId = uint", text)

    def test_reason_codes_have_explicit_wire_values_and_localization_keys(self):
        text = TYPES_PATH.read_text(encoding="utf-8")
        reason_block = text.split("enum class CollectionReasonCode", 1)[1].split("};", 1)[0]
        members = re.findall(r"^\s*([A-Za-z0-9_]+)\s*=\s*(0x[0-9A-Fa-f]+|[0-9]+)", reason_block, re.MULTILINE)
        self.assertGreaterEqual(len(members), 10)
        self.assertEqual(len(members), len({value for _, value in members}))
        self.assertIn("ToStableReasonCode", text)
        self.assertIn("ParseStableReasonCode", text)
        self.assertIn("ReasonCodeLocalizationKey", text)
        self.assertNotIn("static_cast<std::uint16_t>(reason)", text)
        for key in (
            "SC_REASON_OK",
            "SC_REASON_NOT_READY",
            "SC_REASON_NOT_OWNED",
            "SC_REASON_TOMBSTONED",
        ):
            self.assertIn(key, text)

    def test_availability_axes_are_independent(self):
        text = TYPES_PATH.read_text(encoding="utf-8")
        availability = text.split("struct CollectionAvailability", 1)[1].split("};", 1)[0]
        for field in ("Owned", "UsableNow", "CatalogKnown", "AssetReady"):
            self.assertRegex(availability, rf"bool\s+{field}\s*=\s*false")
        self.assertIn("struct CollectionResult", text)
        self.assertIn("CollectionAvailability Availability", text)
        self.assertIn("CollectionRevision Revision", text)

    def test_tombstones_are_first_class_and_not_bindable(self):
        text = TYPES_PATH.read_text(encoding="utf-8")
        self.assertIn("enum class StableIdLifecycle", text)
        self.assertRegex(text, r"Tombstone\s*=\s*2")
        self.assertIn("struct StableIdReservation", text)
        self.assertIn("IsTombstone()", text)
        self.assertIn("CanBind()", text)


if __name__ == "__main__":
    unittest.main()
