from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


class SetCatalogContractTests(unittest.TestCase):
    def test_set_provider_depends_on_appearance_and_projects_owned_state(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        provider = (SRC / "SoloCollectionsProvider.h").read_text(encoding="utf-8")
        account = (SRC / "SoloCollectionsAccountService.cpp").read_text(encoding="utf-8")
        self.assertIn("SetCollectionProvider", core)
        self.assertIn("SetAppearanceDependencyTypeId", core)
        self.assertIn("GetSetCatalog().CompletedByAccount", core)
        self.assertIn("OwnedByAccount", provider)
        self.assertIn("provider->OwnedByAccount", account)

    def test_set_completion_is_derived_from_required_canonical_appearance_members(self):
        header = (SRC / "SoloCollectionsSetCatalog.h").read_text(encoding="utf-8")
        implementation = (SRC / "SoloCollectionsSetCatalog.cpp").read_text(encoding="utf-8")
        generated = (SRC / "generated/SoloCollectionsSetCatalog.inc").read_text(encoding="utf-8")
        self.assertIn("AppearanceAlternatives", header)
        self.assertIn("member.Enabled && member.Required", implementation)
        self.assertIn("SetAppearanceDependencyTypeId", implementation)
        self.assertIn("if (owned)", implementation)
        self.assertEqual(8, generated.count("{ CollectionId{ 3000"))

    def test_no_parallel_set_collected_writer_exists(self):
        production = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in SRC.rglob("*") if path.suffix in {".cpp", ".h"}
        )
        self.assertNotIn("set_collected", production.lower())
        self.assertNotIn("TryUnlock(accountId, { SetCollectionTypeId", production)

    def test_set_apply_resolves_owned_canonical_members_before_one_atomic_commit(self):
        service = (SRC / "SoloCollectionsSetService.cpp").read_text(encoding="utf-8")
        appearance = (SRC / "Categories/Appearance/SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        protocol = (SRC / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        for token in (
            "SelectVariant(accountId, *definition, variantIndex)",
            "runtimeClass.Identity->LogicalId != requiredClass.Identity->LogicalId",
            "member.Enabled",
            "member.Required",
            "GetItemByPos(INVENTORY_SLOT_BAG_0, *slot)",
            "ResolveOwnedSource(player, appearanceId, *slot)",
            "TryApplyCollectedAppearances",
        ):
            self.assertIn(token, service)
        self.assertIn("std::map<std::uint8_t, std::uint32_t> resolved", appearance)
        self.assertIn("PreflightApply(player, requests", transmog)
        self.assertIn("AsyncCommitTransaction(transaction)", transmog)
        self.assertLess(transmog.index("if (!committed)"), transmog.index("player->DestroyItemCount"))
        self.assertIn("request.TypeId == SetCollectionTypeId.Value()", protocol)
        self.assertIn('request.ActionId != "APPLY"', protocol)

    def test_set_slot_mapping_is_explicit_and_unknown_or_duplicate_slots_fail_closed(self):
        service = (SRC / "SoloCollectionsSetService.cpp").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        for slot in (
            "HEAD", "SHOULDER", "SHIRT", "CHEST", "ROBE", "WAIST", "LEGS",
            "FEET", "WRIST", "HANDS", "BACK", "MAINHAND", "OFFHAND", "TABARD",
        ):
            self.assertIn(f'"{slot}"', service)
        self.assertIn("if (!slot)", service)
        self.assertIn("if (!requestedSlots.insert(*slot).second)", service)
        self.assertIn("LANG_TRANSMOG_INVALID_SLOT", service)
        self.assertIn("LANG_TRANSMOG_MISSING_DEST_ITEM", service)
        self.assertIn('slotKey == "CHEST" || slotKey == "ROBE"', service)
        self.assertIn("itemEntry == HIDDEN_ITEM_ID ? UINT_MAX : itemEntry", transmog)
        self.assertIn("request.SourceItemEntry == UINT_MAX", transmog)
        self.assertIn("targetType == INVTYPE_WEAPONMAINHAND || targetType == INVTYPE_WEAPONOFFHAND", transmog)
        self.assertIn("targetType == INVTYPE_CHEST || targetType == INVTYPE_ROBE", transmog)


if __name__ == "__main__":
    unittest.main()
