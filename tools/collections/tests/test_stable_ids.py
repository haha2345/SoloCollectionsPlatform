from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from common import ROOT


GENERATOR_PATH = ROOT / "tools" / "catalog" / "generate_catalog.py"
SPEC = importlib.util.spec_from_file_location("solo_catalog_stable_ids", GENERATOR_PATH)
generator = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(generator)


class StableIdTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stable-id-test-", dir=ROOT)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "catalog", self.root / "catalog")
        self.source = self.root / "catalog" / "source"

    def tearDown(self):
        self.temp.cleanup()

    def load(self, relative: str):
        return json.loads((self.root / relative).read_text(encoding="utf-8"))

    def save(self, relative: str, value):
        (self.root / relative).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def test_duplicate_stable_id_is_rejected(self):
        ids = self.load("catalog/ids.json")
        ids["reservations"]["classes"][1]["id"] = ids["reservations"]["classes"][0]["id"]
        self.save("catalog/ids.json", ids)
        with self.assertRaisesRegex(generator.CatalogError, "duplicate classes reservations id"):
            generator.build_model(self.source)

    def test_unreserved_collection_is_rejected_then_changes_hash_when_reserved(self):
        ids = self.load("catalog/ids.json")
        ordinal = len(ids["reservations"]["collections"])
        csv_path = self.source / "collections" / "companions.csv"
        with csv_path.open("a", encoding="utf-8", newline="") as handle:
            handle.write(f"companion,1000,test_companion,{ordinal},active,Test Companion,测试宠物,unrestricted,3.3.5.12340,spell,123,COMPANION_SPELL,123,true,companion.test,TEST_COMPANION\n")
        actions = self.load("catalog/source/companion_actions.json")
        actions["entries"].append(
            {"collectionId": 1000, "collectionKey": "test_companion", "ordinal": ordinal, "creatureId": 999999}
        )
        self.save("catalog/source/companion_actions.json", actions)

        with self.assertRaisesRegex(generator.CatalogError, "unreserved collections identity"):
            generator.build_model(self.source)

        ids["reservations"]["collections"].append(
            {"id": 1000, "key": "test_companion", "ordinal": ordinal, "lifecycle": "active"}
        )
        self.save("catalog/ids.json", ids)
        presentations = self.load("catalog/source/creature_presentations.json")
        presentations["entries"].append(
            {
                "typeKey": "companion",
                "collectionId": 1000,
                "collectionKey": "test_companion",
                "lifecycle": "active",
                "presentationStatus": "READY",
                "reasonCode": "",
                "previewCreatureEntry": 999999,
                "iconSpellId": 123,
                "spellIconId": 1,
                "iconTexture": "Interface\\Icons\\Test_Companion",
                "sourceBuild": "3.3.5.12340",
            }
        )
        presentations["presentationHash"] = generator._hash(presentations["entries"])
        self.save("catalog/source/creature_presentations.json", presentations)
        populated = generator.build_model(self.source)
        empty = generator.build_model(ROOT / "catalog" / "source")
        self.assertNotEqual(empty["mappingHash"], populated["mappingHash"])
        self.assertEqual("test_companion", populated["collections"][-1]["collectionKey"])

    def test_runtime_id_can_change_without_changing_logical_id(self):
        before = generator.build_model(self.source)
        classes = self.load("catalog/source/classes.json")
        classes["entries"][0]["runtimeClassId"] = 101
        classes["entries"][0]["sourceId"] = 101
        self.save("catalog/source/classes.json", classes)
        after = generator.build_model(self.source)
        self.assertEqual(before["classes"][0]["logicalClassId"], after["classes"][0]["logicalClassId"])
        self.assertNotEqual(before["classes"][0]["runtimeClassId"], after["classes"][0]["runtimeClassId"])


if __name__ == "__main__":
    unittest.main()
