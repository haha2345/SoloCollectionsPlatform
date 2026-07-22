from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
DATA = ROOT / "data" / "generated"


class CompanionProviderContractTests(unittest.TestCase):
    def test_generated_allowlist_contains_only_explicit_minipets(self):
        actions = json.loads((DATA / "solo_collections_companion_actions.json").read_text(encoding="utf-8"))
        self.assertEqual(2, actions["schemaVersion"])
        self.assertEqual(201, len(actions["entries"]))
        unlocks = [spell for row in actions["entries"] for spell in row["unlockSpellIds"]]
        self.assertEqual(203, len(unlocks))
        self.assertEqual(len(unlocks), len(set(unlocks)))
        self.assertTrue(all(row["canonicalSpellId"] in row["unlockSpellIds"] for row in actions["entries"]))
        self.assertTrue(all(row["previewCreatureEntry"] > 0 for row in actions["entries"]))
        generated = (SRC / "generated" / "SoloCollectionsCompanionCatalog.inc").read_text(encoding="utf-8")
        self.assertIn("LoadGeneratedCompanionCollections", generated)

    def test_unlocks_are_spell_allowlisted_migrated_and_account_serialized(self):
        service = (SRC / "SoloCollectionsCompanionService.cpp").read_text(encoding="utf-8")
        self.assertIn("GetCompanionCatalog().FindBySpell(spellId)", service)
        self.assertIn("CompanionSpellMigrationId = 2", service)
        self.assertIn("CheckMigrationMarker", service)
        self.assertIn("HasPendingMutation(account)", service)
        self.assertIn("CompanionCollectionTypeId", service)
        self.assertIn("for (std::uint32_t spellId : definition.UnlockSpellIds)", service)
        self.assertIn("definition->CanonicalSpellId", service)
        self.assertNotIn("CollectionMutationKind::Revoke", service)

    def test_toggle_and_replacement_never_touch_combat_pet_state(self):
        service = (SRC / "SoloCollectionsCompanionService.cpp").read_text(encoding="utf-8")
        protocol = (SRC / "SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
        self.assertIn("player->GetCompanionPet()", service)
        self.assertIn("UNIT_CREATED_BY_SPELL", service)
        self.assertIn("current->DespawnOrUnsummon()", service)
        self.assertNotIn("GetGuardianPet", service)
        self.assertNotIn("SetPetGUID", service)
        self.assertNotIn("GetCritterGUID", service)
        self.assertIn('"DISMISSED"', protocol)


class ToyProviderContractTests(unittest.TestCase):
    def test_every_toy_declares_handler_target_cooldown_and_replay_semantics(self):
        actions = json.loads((DATA / "solo_collections_toy_actions.json").read_text(encoding="utf-8"))
        self.assertEqual(
            {"SPELL_SELF", "SPELL_TARGET", "ITEM_USE", "CUSTOM_HANDLER"},
            {row["actionKind"] for row in actions["entries"]},
        )
        for row in actions["entries"]:
            self.assertIn(row["targetPolicy"], {"SELF", "CURRENT_TARGET"})
            self.assertIn(row["cooldownScope"], {"CHARACTER", "ACCOUNT"})
            self.assertEqual("SC2_REQUEST_ID", row["replayPolicy"])
            self.assertIsInstance(row["allowInCombat"], bool)
            self.assertIsInstance(row["consumesMaterial"], bool)
            self.assertIsInstance(row["riskFlags"], list)

    def test_action_registry_is_allowlisted_and_server_authoritative(self):
        service = (SRC / "SoloCollectionsToyService.cpp").read_text(encoding="utf-8")
        protocol = (SRC / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        self.assertIn('_customHandlers.emplace("unusual_compass"', service)
        self.assertIn("GetToyCatalog().Find(collectionId)", service)
        self.assertIn("GetAccountCollectionCache().IsOwned", service)
        self.assertIn("player->HasSpellCooldown", service)
        self.assertIn("_accountCooldowns", service)
        self.assertIn("request.TypeId == ToyCollectionTypeId.Value()", protocol)
        self.assertIn('request.ActionId != "USE"', protocol)

    def test_risky_toys_use_item_pipeline_and_no_economy_or_teleport_is_allowlisted(self):
        actions = json.loads((DATA / "solo_collections_toy_actions.json").read_text(encoding="utf-8"))
        risks = {flag for row in actions["entries"] for flag in row["riskFlags"]}
        self.assertNotIn("TELEPORT", risks)
        self.assertNotIn("GENERATES_ITEM", risks)
        self.assertNotIn("ECONOMY", risks)
        service = (SRC / "SoloCollectionsToyService.cpp").read_text(encoding="utf-8")
        self.assertIn("player->CanUseItem(item)", service)
        self.assertIn("player->CastItemUseSpell", service)

    def test_item_unlock_hooks_converge_on_one_idempotent_queue(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        service = (SRC / "SoloCollectionsToyService.cpp").read_text(encoding="utf-8")
        for hook in ("OnPlayerStoreNewItem", "OnPlayerCreateItem", "OnPlayerQuestRewardItem",
                     "OnPlayerAfterStoreOrEquipNewItem"):
            self.assertIn(hook, core)
        self.assertIn("GetToyCollectionService().OnItemAcquired", core)
        self.assertIn("state.QueuedCollections.insert", service)


if __name__ == "__main__":
    unittest.main()
