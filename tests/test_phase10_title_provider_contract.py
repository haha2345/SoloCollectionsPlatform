from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
SERVICE = (ROOT / "src/SoloCollectionsTitleService.cpp").read_text(encoding="utf-8")
SERVICE_HEADER = (ROOT / "src/SoloCollectionsTitleService.h").read_text(encoding="utf-8")
SCRIPT = (ROOT / "src/SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
SERVER = (ROOT / "src/SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
PROTOCOL_TEST = (ROOT / "tests/native/SoloCollectionsProtocolTests.cpp").read_text(encoding="utf-8")


class TitleProviderContractTests(unittest.TestCase):
    def test_title_provider_is_stable_external_and_read_only(self):
        self.assertIn("TitleCollectionTypeId { std::uint16_t { 15 } }", SERVICE_HEADER)
        self.assertIn('_descriptor.TypeKey = "title"', CORE)
        self.assertIn("CollectionStorageMode::External", CORE)
        self.assertNotIn("TryUnlock", SERVICE)
        self.assertNotIn("account_collection_unlock", SERVICE)

    def test_core_title_bits_map_to_client_title_indices(self):
        self.assertIn("title->bit_index == bitIndex", SERVICE)
        self.assertIn("title->bit_index + 1", SERVICE)
        self.assertIn("player->HasTitle(title)", SERVICE)
        self.assertIn("sCharTitlesStore", SERVICE)

    def test_external_ownership_is_refreshed_from_the_current_player(self):
        self.assertGreaterEqual(SCRIPT.count("GetTitleService().OwnedByPlayer(player)"), 2)
        self.assertIn("SetExternalOwned", SCRIPT)
        self.assertIn("session.ExternalOwned", SERVER)
        self.assertIn("external title ownership leaked between character sessions", PROTOCOL_TEST)

    def test_title_requests_have_no_action_branch(self):
        action_region = SCRIPT[SCRIPT.index("if (request.TypeId == MountCollectionTypeId.Value())") :]
        self.assertNotIn("request.TypeId == TitleCollectionTypeId.Value()", action_region)


if __name__ == "__main__":
    unittest.main()
