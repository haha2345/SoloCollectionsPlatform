from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from common import ROOT


GENERATOR_PATH = ROOT / "tools" / "catalog" / "generate_catalog.py"
MODULE_ROOT = ROOT.parent / "mod-solo-collections"
SPEC = importlib.util.spec_from_file_location("solo_catalog_generator", GENERATOR_PATH)
generator = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(generator)


class CatalogGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="catalog-test-", dir=ROOT)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "catalog", self.root / "catalog")
        self.source = self.root / "catalog" / "source"

    def tearDown(self):
        self.temp.cleanup()

    def read_json(self, relative: str):
        return json.loads((self.root / relative).read_text(encoding="utf-8"))

    def write_json(self, relative: str, value):
        (self.root / relative).write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def test_checked_in_outputs_are_current(self):
        result = subprocess.run(
            [sys.executable, str(GENERATOR_PATH), "--module-root", str(MODULE_ROOT), "--check"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(str(MODULE_ROOT.resolve()), result.stdout)

    def test_rendering_is_deterministic(self):
        model = generator.build_model(self.source)
        first = generator.render_outputs(model, ROOT, MODULE_ROOT)
        second = generator.render_outputs(generator.build_model(self.source), ROOT, MODULE_ROOT)
        self.assertEqual(first, second)

    def test_protocol_catalog_descriptor_is_generated_for_cpp(self):
        outputs = generator.render_outputs(generator.build_model(self.source), ROOT, MODULE_ROOT)
        target = MODULE_ROOT / "src/generated/SoloCollectionsProtocolCatalog.inc"
        self.assertIn(target, outputs)
        rendered = outputs[target]
        self.assertIn("GeneratedCatalogSchemaVersion", rendered)
        self.assertIn("GeneratedCatalogVersion", rendered)
        self.assertIn("GeneratedIdentityVersion", rendered)
        self.assertIn("GeneratedSc2MetadataVersion", rendered)
        self.assertIn("GeneratedSc2AssetPackVersion", rendered)
        self.assertIn("LoadGeneratedSc2Categories", rendered)
        self.assertIn("typeMappingHashes", generator.build_model(self.source))

    def test_legacy_sc1_shadow_mapping_is_generated_from_the_tracked_lua(self):
        outputs = generator.render_outputs(generator.build_model(self.source), ROOT, MODULE_ROOT)
        json_target = ROOT / "catalog/generated/legacy-sc1-shadow.json"
        cpp_target = MODULE_ROOT / "src/generated/SoloCollectionsLegacyShadowCatalog.inc"
        self.assertIn(json_target, outputs)
        self.assertIn(cpp_target, outputs)
        shadow = json.loads(outputs[json_target])
        by_type = {entry["typeKey"]: entry for entry in shadow["categories"]}
        self.assertEqual((24, 24), (by_type["mount"]["legacyEntryCount"], by_type["mount"]["mappedEntryCount"]))
        self.assertEqual((24, 24), (by_type["companion"]["legacyEntryCount"], by_type["companion"]["mappedEntryCount"]))
        self.assertEqual((36, 4), (by_type["toy"]["legacyEntryCount"], by_type["toy"]["mappedEntryCount"]))
        source = (ROOT / "server/ale/solo_collections.lua").read_text(encoding="utf-8")
        source = source.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
        self.assertEqual(generator.hashlib.sha256(source).hexdigest(), shadow["sourceHash"])
        self.assertIn("LoadGeneratedLegacyShadowEntries", outputs[cpp_target])

    def test_race_presentation_profiles_inherit_the_asset_pack_version(self):
        model = generator.build_model(self.source)
        expected_version = model["assetPackVersion"]
        for race in model["races"]:
            self.assertEqual(expected_version, race["clientAssetVersion"])
            self.assertEqual(race["compatibilityProfile"], race["appearanceOverrideProfile"])
            self.assertEqual(race["clientAssetProfile"], race["modelProfile"])

    def test_localized_metadata_does_not_change_mapping_hash(self):
        before = generator.build_model(self.source)["mappingHash"]
        classes = self.read_json("catalog/source/classes.json")
        classes["entries"][0]["name"]["zhCN"] = "战士本地化修订"
        classes["entries"][0]["icon"] = "Interface\\Icons\\Temporary"
        self.write_json("catalog/source/classes.json", classes)
        after = generator.build_model(self.source)["mappingHash"]
        self.assertEqual(before, after)

    def test_module_target_guard_rejects_wrong_checkout(self):
        with self.assertRaisesRegex(generator.CatalogError, "basename"):
            generator.validate_module_root(ROOT, ROOT.parent)

    def test_alias_cycle_is_rejected(self):
        ids = self.read_json("catalog/ids.json")
        ids["aliases"] = [
            {"kind": "class", "alias": "alpha", "target": "beta"},
            {"kind": "class", "alias": "beta", "target": "alpha"},
        ]
        self.write_json("catalog/ids.json", ids)
        with self.assertRaisesRegex(generator.CatalogError, "alias cycle"):
            generator.build_model(self.source)

    def test_type_dependency_cycle_is_rejected(self):
        types = self.read_json("catalog/source/collection_types.json")
        by_key = {entry["typeKey"]: entry for entry in types["entries"]}
        by_key["synthetic"]["dependencies"] = ["set"]
        by_key["set"]["dependencies"] = ["synthetic"]
        self.write_json("catalog/source/collection_types.json", types)
        with self.assertRaisesRegex(generator.CatalogError, "dependency cycle"):
            generator.build_model(self.source)

    def test_invalid_policy_reference_is_rejected(self):
        policy = self.read_json("catalog/source/policies/unrestricted.json")
        policy["allowedClassKeys"] = ["demon_hunter"]
        self.write_json("catalog/source/policies/unrestricted.json", policy)
        with self.assertRaisesRegex(generator.CatalogError, "unknown class"):
            generator.build_model(self.source)


if __name__ == "__main__":
    unittest.main()
