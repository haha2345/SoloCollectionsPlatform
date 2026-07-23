from __future__ import annotations

import importlib.util
import json
import hashlib
import tempfile
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools" / "catalog" / "weapon_shadow.py"
SPEC = importlib.util.spec_from_file_location("solo_weapon_shadow_test", TOOL)
assert SPEC and SPEC.loader
shadow = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shadow)

BUNDLE_TOOL = ROOT / "tools" / "catalog" / "weapon_bundle.py"
BUNDLE_SPEC = importlib.util.spec_from_file_location("solo_weapon_bundle_test", BUNDLE_TOOL)
assert BUNDLE_SPEC and BUNDLE_SPEC.loader
bundle = importlib.util.module_from_spec(BUNDLE_SPEC)
BUNDLE_SPEC.loader.exec_module(bundle)

INSTALL_TOOL = ROOT / "tools" / "mpq" / "Install-WeaponShadowBundle.ps1"
SHADOW_AUDIT_EXPORT = ROOT / "tools" / "runtime" / "Export-SoloCollectionsWeaponShadowAudit.ps1"
SHADOW_AUDIT_DATA = ROOT / "tools" / "runtime" / "New-WeaponShadowAuditData.py"
SHADOW_AUDIT_MERGE = ROOT / "tools" / "runtime" / "Merge-SoloCollectionsWeaponShadowAudits.ps1"
SHADOW_AUDIT_START = ROOT / "tools" / "runtime" / "Start-SoloCollectionsWeaponShadowAudit.ps1"
SHADOW_AUDIT_ADDON = ROOT / "tools" / "runtime" / "SoloCollectionsWeaponShadowAudit" / "WeaponShadowAudit.lua"


def _row(appearance_id: int, *, geometry: str = "g", display: str = "d") -> dict:
    return {
        "appearanceId": appearance_id,
        "collectionKey": f"appearance.fixture.{appearance_id}",
        "primarySourceItemId": appearance_id + 1000,
        "public": True,
        "terminalStatus": "READY",
        "geometryKey": geometry,
        "textureKey": "t-" + geometry,
        "displayKey": display,
        "modelSignature": "m2:" + geometry,
    }


def _reserved() -> dict:
    entries = []
    for index in range(21):
        entries.append({
            "appearanceId": index + 1,
            "sourceItemId": index + 100,
            "modelId": 4000 + index,
            "syntheticDisplayId": 40000 + index,
            "cameraTuningKey": "ONE_HAND_SWORD",
            "m2Camera": {"yaw": 0, "pitch": 0, "roll": 0, "distanceScale": 1, "target": {"x": 0, "y": 0, "z": 0}},
            "assetHashes": {"m2": f"{index:064x}", "skin": f"{index + 1:064x}", "texture": f"{index + 2:064x}"},
        })
    result = {"schemaVersion": 1, "entries": entries}
    result["reservedImportHash"] = shadow.hashlib.sha256(shadow.canonical(result)).hexdigest()
    return result


class WeaponShadowTests(unittest.TestCase):
    def test_real_candidate_basis_has_the_fixed_public_and_full_denominators(self):
        visibility = json.loads((ROOT / "catalog/review/appearances/visibility-evidence.json").read_text(encoding="utf-8"))
        appearances = json.loads((ROOT / "catalog/generated/appearance-sources.json").read_text(encoding="utf-8"))
        basis, facts = shadow.candidate_basis(visibility, appearances)
        self.assertEqual({"all": 5957, "public": 3690}, basis["counts"])
        self.assertGreater(len(facts), 7000)
        self.assertEqual(5957, len(basis["candidates"]))

    def test_offhand_routes_right_only_when_a_complete_right_pair_exists(self):
        display = {
            "leftModel": "left.mdx", "leftTexture": "left",
            "rightModel": "right.mdx", "rightTexture": "right",
        }
        self.assertEqual(("LEFT", "left.mdx", "left", []), shadow.select_side("MAINHAND", display))
        self.assertEqual(("RIGHT", "right.mdx", "right", []), shadow.select_side("SHIELD", display))
        fallback = shadow.select_side("OFFHAND_WEAPON", {
            "leftModel": "left.mdx", "leftTexture": "left", "rightModel": "right.mdx", "rightTexture": "",
        })
        self.assertEqual("LEFT", fallback[0])
        self.assertIn("OFFHAND_RIGHT_PAIR_UNAVAILABLE_USED_LEFT", fallback[3])

    def test_registry_reuses_display_rows_and_tombstones_never_recycle_ids(self):
        reserved = _reserved()
        base_rows = [_row(index + 1, geometry=f"reserved-source-{index}", display=f"reserved-display-{index}")
                     for index in range(21)]
        first = shadow.registry(
            base_rows + [_row(100, geometry="g-a", display="d-share"), _row(101, geometry="g-b", display="d-share")],
            reserved, "input-hash", None,
        )
        by_appearance = {row["appearanceId"]: row for row in first["entries"]}
        self.assertEqual(by_appearance[100]["syntheticDisplayId"], by_appearance[101]["syntheticDisplayId"])
        self.assertNotEqual(by_appearance[100]["modelId"], by_appearance[101]["modelId"])

        second = shadow.registry(
            base_rows + [_row(101, geometry="g-b", display="d-share"), _row(102, geometry="g-c", display="d-new")],
            reserved, "input-hash", first,
        )
        tombstones = {row["appearanceId"]: row for row in second["tombstones"]}
        self.assertIn(100, tombstones)
        next_row = {row["appearanceId"]: row for row in second["entries"]}[102]
        self.assertGreater(next_row["modelId"], tombstones[100]["modelId"])
        self.assertGreater(next_row["syntheticDisplayId"], tombstones[100]["syntheticDisplayId"])

    def test_audit_and_check_only_accept_a_named_evidence_root(self):
        source = TOOL.read_text(encoding="utf-8")
        audit_section = source[source.index('for name in ("audit", "check"):'):source.index("args = parser.parse_args")]
        self.assertIn("--evidence-root", audit_section)
        self.assertNotIn("--client-data-root", audit_section)

    def test_transformed_creature_model_target_is_windows_style_for_dbc(self):
        target = bundle.creature_model_target(4021)
        self.assertEqual("Item\\ObjectComponents\\SoloCollections\\SCW_M4021", target)
        self.assertNotIn("/", target)
        with self.assertRaises(bundle.WeaponBundleError):
            bundle.creature_model_target(0)

    def test_locale_deployment_requires_the_high_priority_z_patch(self):
        source = INSTALL_TOOL.read_text(encoding="utf-8")
        self.assertIn("Assert-HighPriorityLocaleTarget $localeRelative", source)
        self.assertIn('"patch-$locale-z.MPQ"', source)
        self.assertIn("HIGH_PRIORITY_SUFFIX_Z", source)
        self.assertIn("Numeric suffixes are not a safe priority contract", source)

    def test_shadow_audit_exporter_accepts_the_existing_stage_metadata_shape(self):
        source = SHADOW_AUDIT_EXPORT.read_text(encoding="utf-8")
        starter = SHADOW_AUDIT_START.read_text(encoding="utf-8")
        self.assertIn("bundleStage/stage", source)
        self.assertIn("$runMetadata.PSObject.Properties.Name -contains 'stage'", source)
        self.assertIn("bundleStage=$bundleStage", source)
        self.assertIn("Audit appearance ID is not unique", source)
        self.assertIn("Audit display mismatch for appearance", source)
        self.assertIn("$runBundleId", source)
        self.assertIn("bundleId=$stageManifest.bundleId", starter)
        self.assertIn("Stage manifest identity is invalid", starter)
        self.assertIn("--auto-logout", starter)
        self.assertNotIn("Shadow audit display IDs are not unique", source)

    def test_shadow_audit_supports_manifest_checked_bounded_slices(self):
        data_source = SHADOW_AUDIT_DATA.read_text(encoding="utf-8")
        export_source = SHADOW_AUDIT_EXPORT.read_text(encoding="utf-8")
        self.assertIn('"--start-index"', data_source)
        self.assertIn('"--count"', data_source)
        self.assertIn('"--auto-logout"', data_source)
        self.assertIn("audit slice exceeds projection", data_source)
        self.assertIn("Invalid audit selection", export_source)
        self.assertIn("selectionStartIndex", export_source)

    def test_shadow_audit_auto_logout_happens_only_after_completion(self):
        source = SHADOW_AUDIT_ADDON.read_text(encoding="utf-8")
        self.assertIn("SoloCollectionsWeaponShadowAuditDB.completed = true", source)
        self.assertIn("if DATA.autoLogout then", source)
        self.assertIn("state.logoutAt", source)
        self.assertIn("if state.phase == \"logout\" then", source)
        self.assertIn("Logout()", source)

    def test_shadow_audit_slice_order_breaks_shared_display_ties_by_appearance(self):
        data_source = SHADOW_AUDIT_DATA.read_text(encoding="utf-8")
        export_source = SHADOW_AUDIT_EXPORT.read_text(encoding="utf-8")
        merge_source = SHADOW_AUDIT_MERGE.read_text(encoding="utf-8")
        self.assertIn('(int(value["syntheticDisplayId"]), int(value["appearanceId"]))', data_source)
        self.assertIn('[int]$_.syntheticDisplayId }; Ascending = $true', export_source)
        self.assertIn('[int]$_.appearanceId }; Ascending = $true', export_source)
        self.assertIn('[int]$_.appearanceId }; Ascending = $true', merge_source)

    def test_shadow_audit_aggregate_requires_exact_stage_coverage(self):
        source = SHADOW_AUDIT_MERGE.read_text(encoding="utf-8")
        self.assertIn("All stage appearances are not covered", source)
        self.assertIn("Aggregate appearance is duplicated", source)
        self.assertIn("stageBundleManifestHash", source)
        self.assertIn("$runBundleId", source)
        self.assertIn("$summary.bundleId", source)

    def test_runtime_quarantine_tombstones_an_unsafe_active_asset_without_reusing_its_ids(self):
        """A real-client crash must turn one active presentation into a tombstone.

        The fixture deliberately keeps the immutable 21-entry reserve because
        the production registry verifier treats that imported baseline as a
        hard contract rather than a convenient test-only shortcut.
        """

        with tempfile.TemporaryDirectory(dir=ROOT / "_work") as tempdir:
            temp = Path(tempdir)
            review = temp / "review"
            evidence = temp / "runtime-evidence"
            output = temp / "runtime-output"
            review.mkdir()
            (evidence / "audit").mkdir(parents=True)
            crash = evidence / "audit" / "crash.txt"
            crash.write_text("ERROR #132", encoding="utf-8")

            fields = [
                "appearanceId", "scope", "terminalStatus", "assetStatus", "presentationStatus",
                "reasonCodes", "missingRelativePaths", "allocationStatus", "modelId",
                "syntheticDisplayId", "collectionKey", "primarySourceItemId", "modelSignature",
            ]
            rows = []
            entries = []
            for index in range(21):
                appearance_id = index + 1
                entries.append({
                    "appearanceId": appearance_id,
                    "collectionKey": f"appearance.reserve.{appearance_id}",
                    "sourceItemId": appearance_id + 100,
                    "allocationStatus": "RESERVED",
                    "modelId": 4000 + index,
                    "syntheticDisplayId": 40000 + index,
                    "geometryKey": f"reserved-geometry-{appearance_id}",
                    "textureKey": f"reserved-texture-{appearance_id}",
                    "displayKey": f"reserved-display-{appearance_id}",
                    "modelSignature": f"m2:reserved-{appearance_id}",
                })
                rows.append({
                    "appearanceId": str(appearance_id), "scope": "PUBLIC", "terminalStatus": "READY",
                    "assetStatus": "READY", "presentationStatus": "INHERITED_VERIFIED", "reasonCodes": "READY",
                    "missingRelativePaths": "", "allocationStatus": "RESERVED", "modelId": str(4000 + index),
                    "syntheticDisplayId": str(40000 + index), "collectionKey": f"appearance.reserve.{appearance_id}",
                    "primarySourceItemId": str(appearance_id + 100), "modelSignature": f"m2:reserved-{appearance_id}",
                })
            entries.append({
                "appearanceId": 100,
                "collectionKey": "appearance.runtime.100",
                "sourceItemId": 1100,
                "allocationStatus": "ACTIVE",
                "modelId": 5000,
                "syntheticDisplayId": 42000,
                "geometryKey": "geometry-runtime",
                "textureKey": "texture-runtime",
                "displayKey": "display-runtime",
                "modelSignature": "m2:runtime",
            })
            rows.append({
                "appearanceId": "100", "scope": "PUBLIC", "terminalStatus": "READY",
                "assetStatus": "READY", "presentationStatus": "SHADOW_READY", "reasonCodes": "READY",
                "missingRelativePaths": "", "allocationStatus": "ACTIVE", "modelId": "5000",
                "syntheticDisplayId": "42000", "collectionKey": "appearance.runtime.100",
                "primarySourceItemId": "1100", "modelSignature": "m2:runtime",
            })
            candidate_text = shadow._runtime_csv_text(fields, rows)
            (review / "shadow-candidates.csv").write_text(candidate_text, encoding="utf-8", newline="\n")
            registry = {
                "schemaVersion": 1,
                "inputHash": "fixture-input",
                "reservedImportHash": "fixture-reserve",
                "idRanges": {
                    "reservedModelIds": [4000, 4020], "reservedDisplayIds": [40000, 40020],
                    "nextModelId": 5001, "nextSyntheticDisplayId": 42001,
                },
                "entries": entries,
                "tombstones": [],
                "dedup": {"readyPublicAppearances": 22, "reservedAppearances": 21,
                          "newlyAllocatedAppearances": 1, "uniqueNewGeometry": 1,
                          "uniqueNewDisplays": 1, "reusedGeometryAppearances": 0,
                          "reusedDisplayAppearances": 0},
            }
            registry["registryHash"] = hashlib.sha256(shadow.canonical(registry)).hexdigest()
            (review / "shadow-registry.json").write_text(json.dumps(registry, sort_keys=True), encoding="utf-8")
            summary = {
                "schemaVersion": 1,
                "registryHash": registry["registryHash"],
                "candidateCsvSha256": hashlib.sha256(candidate_text.encode("utf-8")).hexdigest(),
                "denominators": {"public": 22, "allWeaponCandidates": 22},
                "terminalCounts": {"publicReady": 22, "publicUnavailable": 0, "nonpublic": 0},
                "reasonCodeCounts": {},
                "rawSourceAssetReasonCodeCounts": {},
                "dedup": registry["dedup"],
            }
            summary["summaryHash"] = hashlib.sha256(shadow.canonical(summary)).hexdigest()
            (review / "shadow-summary.json").write_text(json.dumps(summary, sort_keys=True), encoding="utf-8")
            quarantine = {
                "schemaVersion": 1,
                "kind": "SoloCollectionsWeaponRuntimeQuarantine",
                "baseReview": {
                    "summaryHash": summary["summaryHash"],
                    "registryHash": registry["registryHash"],
                    "candidateCsvSha256": summary["candidateCsvSha256"],
                },
                "entries": [{
                    "appearanceId": 100,
                    "quarantineId": "fixture-132",
                    "reasonCode": "CLIENT_RUNTIME_CRASH_132",
                    "collectionKey": "appearance.runtime.100",
                    "sourceItemId": 1100,
                    "modelId": 5000,
                    "syntheticDisplayId": 42000,
                    "modelSignature": "m2:runtime",
                    "evidenceFiles": [{
                        "relativePath": "audit/crash.txt",
                        "size": crash.stat().st_size,
                        "sha256": hashlib.sha256(crash.read_bytes()).hexdigest(),
                    }],
                }],
            }
            quarantine["quarantineHash"] = hashlib.sha256(shadow.canonical(quarantine)).hexdigest()
            quarantine_path = temp / "runtime-quarantine.json"
            quarantine_path.write_text(json.dumps(quarantine, sort_keys=True), encoding="utf-8")

            result = shadow.runtime_projection(review, quarantine_path, evidence, output, False)
            self.assertEqual(1, result["runtimeQuarantineCount"])
            self.assertEqual({"publicReady": 21, "publicUnavailable": 1, "nonpublic": 0}, result["terminalCounts"])
            shadow.runtime_projection(review, quarantine_path, evidence, output, True)
            runtime_registry = json.loads((output / "shadow-registry.json").read_text(encoding="utf-8"))
            self.assertNotIn(100, {entry["appearanceId"] for entry in runtime_registry["entries"]})
            tombstone = runtime_registry["tombstones"][0]
            self.assertEqual((5000, 42000, "CLIENT_RUNTIME_CRASH_132"),
                             (tombstone["modelId"], tombstone["syntheticDisplayId"], tombstone["tombstoneReason"]))


if __name__ == "__main__":
    unittest.main()
