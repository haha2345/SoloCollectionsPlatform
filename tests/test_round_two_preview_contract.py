from __future__ import annotations

import unittest
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


class RoundTwoPreviewContractTests(unittest.TestCase):
    def test_preview_service_uses_trusted_catalog_and_core_query_handler(self):
        header = (SRC / "SoloCollectionsCreaturePreviewService.h").read_text(encoding="utf-8")
        source = (SRC / "SoloCollectionsCreaturePreviewService.cpp").read_text(encoding="utf-8")
        self.assertRegex(
            header,
            r"CreaturePreviewResult\s+Execute\(\s*Player\* player, CollectionTypeId typeId, CollectionId collectionId\) const",
        )
        for token in (
            "GetMountCatalog().Find(collectionId)",
            "GetCompanionCatalog().Find(collectionId)",
            "PreviewCreatureEntry",
            "sObjectMgr->GetCreatureTemplate",
            "HandleCreatureQueryOpcode",
            "ObjectGuid::Empty",
        ):
            self.assertIn(token, source)
        for forbidden in ("WorldDatabase", "CharacterDatabase", "CastSpell(", "SummonCreature(", "SaveToDB("):
            self.assertNotIn(forbidden, source)

    def test_sc2_server_persists_hello_versions_and_gates_every_action(self):
        header = (SRC / "SoloCollectionsProtocolServer.h").read_text(encoding="utf-8")
        source = (SRC / "SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
        for token in ("ClientMetadataVersion", "ClientAssetPackVersion"):
            self.assertIn(token, header)
        for token in (
            "session.ClientMetadataVersion = message.MetadataVersion",
            "session.ClientAssetPackVersion = message.AssetPackVersion",
            'result.Status = "CATALOG_MISMATCH"',
            'message.ActionId == "PREVIEW"',
            'result.Status = "ASSET_MISMATCH"',
        ):
            self.assertIn(token, source)

    def test_generated_creature_catalogs_publish_lifecycle_and_preview_entry(self):
        for name in ("SoloCollectionsMountCatalog.h", "SoloCollectionsCompanionCatalog.h"):
            text = (SRC / name).read_text(encoding="utf-8")
            self.assertIn("PreviewCreatureEntry", text)
            self.assertIn("CatalogLifecycle Lifecycle", text)

    def test_preview_configuration_and_protocol_dispatch_are_explicit(self):
        config = (ROOT / "conf" / "transmog.conf.dist").read_text(encoding="utf-8")
        script = (SRC / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        self.assertIn("SoloCollections.Preview.Enabled = 1", config)
        self.assertIn('request.ActionId == "PREVIEW"', script)
        self.assertIn("GetCreaturePreviewService().Execute", script)
        self.assertIn("entry={} status={} elapsed_us={}", script)


if __name__ == "__main__":
    unittest.main()
