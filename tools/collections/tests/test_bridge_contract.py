from __future__ import annotations

import unittest
import re

from common import ADDON, SERVER_LUA, read_text


def function_region(text: str, name: str) -> str:
    """Return one named Lua function through the next top-level function."""
    start_match = re.search(
        rf"(?m)^(?:local\s+)?function\s+{re.escape(name)}\s*\(",
        text,
    )
    if not start_match:
        raise AssertionError(f"missing Lua function: {name}")
    next_match = re.search(
        r"(?m)^(?:local\s+)?function\s+[A-Za-z0-9_.:]+\s*\(",
        text[start_match.end() :],
    )
    end = len(text) if not next_match else start_match.end() + next_match.start()
    return text[start_match.start() : end]


def lua_table_records(text: str, assignment: str) -> list[str]:
    """Extract top-level Lua record tables without assuming one-line records."""
    assignment_index = text.find(assignment)
    if assignment_index < 0:
        raise AssertionError(f"missing Lua table assignment: {assignment}")
    table_start = text.find("{", assignment_index + len(assignment))
    if table_start < 0:
        raise AssertionError(f"missing opening table brace after: {assignment}")

    records: list[str] = []
    depth = 0
    record_start: int | None = None
    quote: str | None = None
    escaped = False
    for index in range(table_start, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ('"', "'"):
            quote = char
            continue
        if char == "{":
            depth += 1
            if depth == 2:
                record_start = index
        elif char == "}":
            if depth == 2 and record_start is not None:
                records.append(text[record_start : index + 1])
                record_start = None
            depth -= 1
            if depth == 0:
                return records
    raise AssertionError(f"unterminated Lua table assignment: {assignment}")


def server_mount_allowlist(text: str) -> dict[int, tuple[int, int, bool]]:
    """Parse the fixed mountId-to-server-data Lua allowlist."""
    match = re.search(
        r"(?ms)^local\s+MOUNTS\s*=\s*\{(.*?)^\}",
        text,
    )
    if not match:
        raise AssertionError("missing mountId allowlist: MOUNTS")
    parsed: dict[int, tuple[int, int, bool]] = {}
    for mount_id_text, record in re.findall(
        r"\[(\d+)\]\s*=\s*\{(.*?)\}",
        match.group(1),
        re.DOTALL,
    ):
        creature = re.search(r"\bcreatureId\s*=\s*(\d+)", record)
        spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
        collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
        if not creature or not spell or not collected:
            raise AssertionError(f"incomplete server mount record: {mount_id_text}")
        mount_id = int(mount_id_text)
        if mount_id in parsed:
            raise AssertionError(f"duplicate server mountId: {mount_id}")
        parsed[mount_id] = (
            int(creature.group(1)),
            int(spell.group(1)),
            collected.group(1) == "true",
        )
    return parsed


def server_pet_allowlist(text: str) -> dict[int, tuple[int, int, bool]]:
    """Parse the fixed petId-to-server-data Lua allowlist."""
    match = re.search(r"(?ms)^local\s+PETS\s*=\s*\{(.*?)^\}", text)
    if not match:
        raise AssertionError("missing petId allowlist: PETS")
    parsed: dict[int, tuple[int, int, bool]] = {}
    for pet_id_text, record in re.findall(
        r"\[(\d+)\]\s*=\s*\{(.*?)\}", match.group(1), re.DOTALL
    ):
        creature = re.search(r"\bcreatureId\s*=\s*(\d+)", record)
        spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
        collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
        if not creature or not spell or not collected:
            raise AssertionError(f"incomplete server pet record: {pet_id_text}")
        pet_id = int(pet_id_text)
        if pet_id in parsed:
            raise AssertionError(f"duplicate server petId: {pet_id}")
        parsed[pet_id] = (
            int(creature.group(1)),
            int(spell.group(1)),
            collected.group(1) == "true",
        )
    return parsed


def server_toy_allowlist(text: str) -> dict[int, tuple[int, int, bool]]:
    """Parse the fixed toyId-to-server-data Lua allowlist."""
    match = re.search(r"(?ms)^local\s+TOYS\s*=\s*\{(.*?)^\}", text)
    if not match:
        raise AssertionError("missing toyId allowlist: TOYS")
    parsed: dict[int, tuple[int, int, bool]] = {}
    for toy_id_text, record in re.findall(
        r"\[(\d+)\]\s*=\s*\{(.*?)\}", match.group(1), re.DOTALL
    ):
        item = re.search(r"\bitemId\s*=\s*(\d+)", record)
        spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
        collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
        if not item or not spell or not collected:
            raise AssertionError(f"incomplete server toy record: {toy_id_text}")
        toy_id = int(toy_id_text)
        if toy_id in parsed:
            raise AssertionError(f"duplicate server toyId: {toy_id}")
        parsed[toy_id] = (
            int(item.group(1)),
            int(spell.group(1)),
            collected.group(1) == "true",
        )
    return parsed


class BridgeContractTests(unittest.TestCase):
    def test_client_declares_sc1_handshake_and_demo_fallback(self):
        bridge = ADDON / "Core" / "Bridge.lua"
        self.assertTrue(bridge.is_file(), f"missing {bridge}")
        text = read_text(bridge)
        for token in (
            'prefix = "SC1"',
            'request = "HELLO|1"',
            'response = "HELLO_ACK|1|DEMO"',
            "RegisterAddonMessagePrefix",
            "SendAddonMessage",
            '"WHISPER"',
            'UnitName("player")',
            "demoMode",
            "features",
            "timeout",
            'SetScript("OnUpdate"',
        ):
            self.assertIn(token, text)

        timeout = re.search(r"timeout\s*=\s*([0-9]+(?:\.[0-9]+)?)", text)
        self.assertIsNotNone(timeout, "bridge must declare a finite timeout")
        self.assertGreater(float(timeout.group(1)), 0)
        self.assertLessEqual(float(timeout.group(1)), 10)

    def test_client_attempts_once_and_authenticates_the_handshake_ack(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        for token in (
            "B.attempted and not force",
            "B.waiting",
            "B.prefix ~= prefix",
            "B.Finish(false",
            "B.Finish(true",
        ):
            self.assertIn(token, bridge)
        on_message = function_region(bridge, "B.OnMessage")
        self.assertRegex(on_message, r"message\s*[~=]=\s*B\.response")
        self.assertIn('channel ~= "WHISPER"', on_message)
        self.assertIn('sender ~= UnitName("player")', on_message)
        self.assertIn('event == "PLAYER_LOGIN"', bootstrap)
        self.assertIn('command == "reconnect"', bootstrap)
        self.assertIn("SC.Bridge.Connect(true)", bootstrap)

    def test_335_without_prefix_registration_api_still_sends_handshake(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        absence = re.search(
            r"if not RegisterAddonMessagePrefix then\s*(.*?)\s*end",
            bridge,
            re.DOTALL,
        )
        self.assertIsNotNone(absence, "missing 3.3 compatibility branch")
        self.assertIn("prefixRegistered = true", absence.group(1))
        self.assertIn("return true", absence.group(1))

    def test_present_prefix_registration_api_retries_only_real_failures(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        for token in (
            "local function ensurePrefixRegistered()",
            "if not RegisterAddonMessagePrefix then",
            "local ok, registered = pcall(RegisterAddonMessagePrefix, B.prefix)",
            "if ok and registered ~= false then",
            "return prefixRegistered",
            "if not ensurePrefixRegistered() then",
            'B.Finish(false, "fallback")',
        ):
            self.assertIn(token, bridge)

    def test_saved_features_keep_the_runtime_table_shape(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        for token in (
            "local savedFeatures = {}",
            "for feature, enabled in pairs(B.features) do",
            "savedFeatures[feature] = true",
            "SC.db.bridge.features = savedFeatures",
        ):
            self.assertIn(token, bridge)
        self.assertNotIn('SC.db.bridge.features = B.connected and "DEMO" or ""', bridge)

    def test_client_exposes_correlated_model_and_summon_requests(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        for token in (
            "function B.RequestModel(mountId, callback)",
            "function B.SummonMount(collectionId, callback)",
            "requestSerial",
            "pendingModels",
            "sc2PendingActions",
            '"MODEL|"',
            "MODEL_READY|",
            '"SUMMON"',
            "B.RequestSC2Action(10, collectionId",
            "pendingModels[requestId]",
        ):
            self.assertIn(token, bridge)
        self.assertRegex(
            bridge,
            r'string\.match\(message,\s*"\^MODEL_READY\|\(%d\+\)\|\(%d\+\)\$"\)',
        )
        self.assertRegex(bridge, r"pending\.mountId\s*~=\s*mountId")
        on_message = function_region(bridge, "B.OnMessage")
        model_ready = function_region(bridge, "handleModelReady")
        for handler, pending_table in ((model_ready, "pendingModels"),):
            self.assertIn(f"local pending = {pending_table}[requestId]", handler)
            self.assertIn("pending.mountId ~= mountId", handler)
            self.assertIn(f"{pending_table}[requestId] = nil", handler)
            self.assertRegex(
                handler,
                r"(?:pending\.callback\(|pcall\(\s*pending\.callback\s*,)",
            )
        self.assertIn("handleModelReady(", on_message)
        self.assertIn("handleSummonResult(", on_message)
        async_positions = [
            on_message.find("handleModelReady("),
            on_message.find("handleSummonResult("),
        ]
        self.assertTrue(all(position >= 0 for position in async_positions))
        for authentication_guard in (
            "B.prefix ~= prefix",
            'channel ~= "WHISPER"',
            'sender ~= UnitName("player")',
        ):
            guard_position = on_message.find(authentication_guard)
            self.assertGreaterEqual(guard_position, 0)
            self.assertLess(
                guard_position,
                min(async_positions),
                f"{authentication_guard} must run before asynchronous dispatch",
            )
        waiting_guard = on_message.find("if not B.waiting")
        self.assertTrue(
            waiting_guard < 0 or waiting_guard > max(async_positions),
            "a top-level waiting guard must not swallow asynchronous bridge responses",
        )

    def test_client_exposes_independent_pet_model_and_summon_requests(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        for token in (
            "pendingPetModels",
            "pendingPetSummons",
            "function B.RequestPetModel(petId, callback)",
            "function B.SummonPet(petId, callback)",
            '"PET_MODEL|"',
            '"PET_SUMMON|"',
            'string.match(message, "^PET_MODEL_READY|(%d+)|(%d+)$")',
            'string.match(message, "^PET_SUMMON_RESULT|(%d+)|(.+)$")',
        ):
            self.assertIn(token, bridge)
        for function_name, pending_table in (
            ("B.RequestPetModel", "pendingPetModels"),
            ("B.SummonPet", "pendingPetSummons"),
        ):
            request = function_region(bridge, function_name)
            self.assertIn("isPositiveInteger(petId)", request)
            self.assertIn(f"{pending_table}[requestId] = {{", request)
            self.assertIn("petId = petId", request)

    def test_client_exposes_correlated_toy_use_requests(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        for token in (
            "pendingToyUses",
            "function B.UseToy(toyId, callback)",
            '"TOY_USE|"',
            'string.match(message, "^TOY_USE_RESULT|(%d+)|(.+)$")',
            "handleToyUseResult(",
        ):
            self.assertIn(token, bridge)
        request = function_region(bridge, "B.UseToy")
        for token in (
            "isPositiveInteger(toyId)",
            'if not B.connected then',
            '"BRIDGE_UNAVAILABLE"',
            "pendingToyUses[requestId] = {",
            "toyId = toyId",
            "deadline = GetTime() + requestTimeout",
        ):
            self.assertIn(token, request)
        handler = function_region(bridge, "handleToyUseResult")
        self.assertIn("local pending = pendingToyUses[requestId]", handler)
        self.assertIn("pending.toyId ~= toyId", handler)
        self.assertIn("pendingToyUses[requestId] = nil", handler)

    def test_client_request_timeouts_clear_all_pending_tables(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        timeout = re.search(r"requestTimeout\s*=\s*([0-9]+(?:\.[0-9]+)?)", bridge)
        self.assertIsNotNone(timeout, "bridge must declare a finite request timeout")
        self.assertGreater(float(timeout.group(1)), 0)
        self.assertLessEqual(float(timeout.group(1)), 10)
        expiry = function_region(bridge, "expirePendingRequests")
        for pending_table in (
            "pendingModels",
            "pendingSummons",
            "pendingPetModels",
            "pendingPetSummons",
            "pendingToyUses",
        ):
            self.assertIn(f"pairs({pending_table})", expiry)
            self.assertIn(f"{pending_table}[requestId] = nil", expiry)
        self.assertIn('"TIMEOUT"', expiry)
        self.assertRegex(
            expiry,
            r"(?:pending\.callback\(|pcall\(\s*pending\.callback\s*,)",
        )
        on_update = re.search(
            r'timerFrame:SetScript\(\s*"OnUpdate"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)',
            bridge,
        )
        self.assertIsNotNone(on_update, "timerFrame must install a named OnUpdate driver")
        timer_handler = function_region(bridge, on_update.group(1))
        self.assertIn(
            "expirePendingRequests(",
            timer_handler,
            "the installed OnUpdate driver must execute pending-request expiry",
        )

    def test_client_requests_validate_ids_fail_fast_and_share_one_timer(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        validator = function_region(bridge, "isPositiveInteger")
        for token in (
            'type(value) == "number"',
            "value > 0",
            "value == math.floor(value)",
        ):
            self.assertIn(token, validator)

        for function_name, pending_table, verb in (("B.RequestModel", "pendingModels", "MODEL"),):
            request = function_region(bridge, function_name)
            for token in (
                "isPositiveInteger(mountId)",
                'if not B.connected then',
                '"BRIDGE_UNAVAILABLE"',
                "requestSerial = requestSerial + 1",
                f"{pending_table}[requestId] = {{",
                "mountId = mountId",
                "deadline = GetTime() + requestTimeout",
                "callback = callback",
                f'"{verb}|"',
                '"WHISPER"',
                'UnitName("player")',
            ):
                self.assertIn(token, request)

        summon = function_region(bridge, "B.SummonMount")
        for token in (
            "isPositiveInteger(collectionId)",
            'if not B.sc2Connected then',
            '"BRIDGE_UNAVAILABLE"',
            'B.RequestSC2Action(10, collectionId, "SUMMON", nil, callback)',
        ):
            self.assertIn(token, summon)
        self.assertNotIn('"SUMMON|"', summon)
        self.assertNotIn("mountId", summon)

        self.assertEqual(
            1,
            bridge.count('local timerFrame = CreateFrame("Frame")'),
            "the handshake and request expiry must share one timer frame",
        )
        self.assertEqual(
            1,
            len(re.findall(r'timerFrame:SetScript\(\s*"OnUpdate"', bridge)),
            "the shared timer driver must be installed only once",
        )
        self.assertNotIn(
            'timerFrame:SetScript("OnUpdate", nil)',
            bridge,
            "finishing the handshake must not disable pending-request expiry",
        )

    def test_client_summon_result_accepts_only_exact_result_shapes(self):
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        handler = function_region(bridge, "handleSummonResult")
        for token in (
            'status == "ACCEPTED"',
            'status == "ERROR"',
            'string.match(payload, "^%d+$")',
            "pending.mountId ~= mountId",
            "pendingSummons[requestId] = nil",
            "pcall(pending.callback, true",
            "pcall(pending.callback, false",
        ):
            self.assertIn(token, handler)
        self.assertIn(
            'string.match(payload, "^[A-Z_]+$")',
            handler,
            "server error reasons must be a single safe protocol token",
        )

    def test_server_bridge_has_no_database_or_inventory_mutations(self):
        self.assertTrue(SERVER_LUA.is_file(), f"missing {SERVER_LUA}")
        text = read_text(SERVER_LUA)
        for token in (
            'local PREFIX = "SC1"',
            'local REQUEST = "HELLO|1"',
            'local RESPONSE = "HELLO_ACK|1|DEMO"',
            "RegisterServerEvent(30, onAddonMessage)",
            "sender:SendAddonMessage(PREFIX, RESPONSE, CHAT_MSG_WHISPER, sender)",
        ):
            self.assertIn(token, text)
        for guard in (
            "if not ENABLED then",
            "if prefix ~= PREFIX then",
        ):
            self.assertIn(guard, text)
        for forbidden in (
            "WorldDBQuery",
            "CharDBQuery",
            "AuthDBQuery",
            "WorldDBExecute",
            "CharDBExecute",
            "LearnSpell",
            "AddItem",
            "RemoveItem",
            "SetCoinage",
            "ModifyMoney",
            "mod-transmog",
            "SaveToDB",
        ):
            self.assertNotIn(forbidden, text)

    def test_server_protocol_uses_strict_numbers_and_explicit_responses(self):
        text = read_text(SERVER_LUA)
        for token in (
            'string.match(message, "^MODEL|(%d+)|(%d+)$")',
            'string.match(message, "^SUMMON|(%d+)|(%d+)$")',
            'string.match(message, "^PET_MODEL|(%d+)|(%d+)$")',
            'string.match(message, "^PET_SUMMON|(%d+)|(%d+)$")',
            'string.match(message, "^TOY_USE|(%d+)|(%d+)$")',
            '"MODEL_READY|"',
            '"SUMMON_RESULT|"',
            '"PET_MODEL_READY|"',
            '"PET_SUMMON_RESULT|"',
            '"TOY_USE_RESULT|"',
            '"ACCEPTED"',
            "PrimeCreatureQuery(",
        ):
            self.assertIn(token, text)
        self.assertNotIn('"SUCCESS"', text)
        parser = function_region(text, "parsePositiveInteger")
        self.assertIn('string.match(value, "^%d+$")', parser)
        self.assertIn("tonumber(value)", parser)
        self.assertGreaterEqual(
            text.count("parsePositiveInteger("),
            5,
            "requestId and mountId must both use the strict parser for MODEL and SUMMON",
        )

    def test_server_model_handler_maps_mount_id_before_priming_the_cache(self):
        text = read_text(SERVER_LUA)
        handler = function_region(text, "handleModel")
        self.assertIn("local mount = MOUNTS[mountId]", handler)
        self.assertRegex(handler, r"if\s+not\s+mount\s+then[\s\S]*?return[\s\S]*?end")
        self.assertIn("sender:PrimeCreatureQuery(mount.creatureId)", handler)
        self.assertIn('"MODEL_READY|"', handler)
        self.assertIn("mountId", handler)

    def test_server_model_ready_requires_a_true_prime_result(self):
        text = read_text(SERVER_LUA)
        handler = function_region(text, "handleModel")
        for token in (
            "local ok, primed = pcall(function()",
            "return sender:PrimeCreatureQuery(mount.creatureId)",
            "if not ok or primed ~= true then",
        ):
            self.assertIn(token, handler)
        self.assertLess(
            handler.index("if not ok or primed ~= true then"),
            handler.index('"MODEL_READY|"'),
            "MODEL_READY must only be sent after a successful true prime result",
        )

    def test_server_total_rate_limit_precedes_all_sc1_responses_and_dispatch(self):
        text = read_text(SERVER_LUA)
        self.assertIn("local TOTAL_LIMIT_PER_SECOND =", text)
        handler = function_region(text, "onAddonMessage")
        total_limit = 'checkRateLimit(sender, "TOTAL", TOTAL_LIMIT_PER_SECOND)'
        self.assertIn(total_limit, handler)
        limit_position = handler.index(total_limit)
        for later_token in (
            "sender:SendAddonMessage(PREFIX, RESPONSE, CHAT_MSG_WHISPER, sender)",
            "handleModel(sender, modelRequestId, modelMountId)",
            "handleSummon(sender, summonRequestId, summonMountId)",
            "handlePetModel(sender, petModelRequestId, petModelId)",
            "handlePetSummon(sender, petSummonRequestId, petSummonId)",
            "handleToyUse(sender, toyUseRequestId, toyUseId)",
        ):
            self.assertIn(later_token, handler)
            self.assertLess(
                limit_position,
                handler.index(later_token),
                f"total SC1 rate limit must precede {later_token}",
            )
        self.assertRegex(
            handler,
            r'if\s+not\s+checkRateLimit\(sender,\s*"TOTAL",\s*TOTAL_LIMIT_PER_SECOND\)\s+then[\s\S]*?return\s+true[\s\S]*?end',
        )

    def test_server_mount_id_allowlist_matches_the_fixed_mount_catalog(self):
        text = read_text(SERVER_LUA)
        mounts = read_text(ADDON / "Data" / "Mounts.lua")
        records = lua_table_records(mounts, "SC.Data.Mounts =")
        self.assertEqual(24, len(records), "the fixed client catalog must contain 24 mounts")
        expected_mounts: dict[int, tuple[int, int, bool]] = {}
        for record in records:
            mount = re.search(r"\bid\s*=\s*(\d+)", record)
            creature = re.search(r"\bcreatureId\s*=\s*(\d+)", record)
            spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
            collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
            self.assertIsNotNone(mount)
            self.assertIsNotNone(creature)
            self.assertIsNotNone(spell)
            self.assertIsNotNone(collected)
            mount_id = int(mount.group(1))
            self.assertNotIn(mount_id, expected_mounts, f"duplicate client mountId: {mount_id}")
            expected_mounts[mount_id] = (
                int(creature.group(1)),
                int(spell.group(1)),
                collected.group(1) == "true",
            )

        server_mounts = server_mount_allowlist(text)
        self.assertEqual(24, len(server_mounts), "the server allowlist must contain 24 mounts")
        self.assertEqual(
            expected_mounts,
            server_mounts,
            "the server must derive creatureId, spellId and collected state from mountId",
        )

    def test_server_pet_id_allowlist_matches_the_fixed_pet_catalog(self):
        text = read_text(SERVER_LUA)
        pets = read_text(ADDON / "Data" / "Pets.lua")
        records = lua_table_records(pets, "SC.Data.Pets =")
        self.assertEqual(24, len(records), "the fixed client catalog must contain 24 pets")
        expected: dict[int, tuple[int, int, bool]] = {}
        for record in records:
            pet = re.search(r"\bid\s*=\s*(\d+)", record)
            creature = re.search(r"\bcreatureId\s*=\s*(\d+)", record)
            spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
            collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
            self.assertIsNotNone(pet)
            self.assertIsNotNone(creature)
            self.assertIsNotNone(spell)
            self.assertIsNotNone(collected)
            expected[int(pet.group(1))] = (
                int(creature.group(1)),
                int(spell.group(1)),
                collected.group(1) == "true",
            )
        self.assertEqual(expected, server_pet_allowlist(text))

    def test_server_toy_id_allowlist_matches_the_fixed_toy_catalog(self):
        text = read_text(SERVER_LUA)
        toys = read_text(ADDON / "Data" / "Toys.lua")
        records = lua_table_records(toys, "SC.Data.Toys =")
        self.assertEqual(36, len(records), "the fixed client catalog must contain 36 toys")
        expected: dict[int, tuple[int, int, bool]] = {}
        for record in records:
            toy = re.search(r"\bid\s*=\s*(\d+)", record)
            item = re.search(r"\bitemId\s*=\s*(\d+)", record)
            spell = re.search(r"\bspellId\s*=\s*(\d+)", record)
            collected = re.search(r"\bcollected\s*=\s*(true|false)", record)
            self.assertIsNotNone(toy)
            self.assertIsNotNone(item)
            self.assertIsNotNone(spell)
            self.assertIsNotNone(collected)
            expected[int(toy.group(1))] = (
                int(item.group(1)),
                int(spell.group(1)),
                collected.group(1) == "true",
            )
        self.assertEqual(expected, server_toy_allowlist(text))

    def test_server_pet_handlers_validate_allowlist_before_prime_or_cast(self):
        text = read_text(SERVER_LUA)
        model = function_region(text, "handlePetModel")
        summon = function_region(text, "handlePetSummon")
        for token in (
            "local pet = PETS[petId]",
            "sender:PrimeCreatureQuery(pet.creatureId)",
            '"PET_MODEL_READY|"',
        ):
            self.assertIn(token, model)
        cast_position = summon.index("sender:CastSpell(sender, spellId, false)")
        self.assertIn("local pet = PETS[petId]", summon[:cast_position])
        self.assertIn("pet.collected", summon[:cast_position])
        self.assertIn("local spellId = pet.spellId", summon[:cast_position])
        self.assertIn('sendPetSummonAccepted(sender, requestId, petId)', summon)

    def test_server_cast_is_confined_to_validated_collection_handlers(self):
        text = read_text(SERVER_LUA)
        handler = function_region(text, "handleSummon")
        cast_calls = re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*:CastSpell\(", text)
        self.assertEqual(
            3,
            len(cast_calls),
            "the server bridge must have exactly three validated cast paths",
        )
        self.assertIn("local mount = MOUNTS[mountId]", handler)
        self.assertRegex(handler, r"if\s+not\s+mount\s+then[\s\S]*?return[\s\S]*?end")
        self.assertRegex(
            handler,
            r"if\s+not\s+mount\.collected\s+then[\s\S]*?return[\s\S]*?end",
        )
        self.assertIn("local spellId = mount.spellId", handler)
        self.assertIn("sender:CastSpell(sender, spellId, false)", handler)
        validation_end = handler.index("sender:CastSpell(sender, spellId, false)")
        validated_prefix = handler[:validation_end]
        self.assertIn("MOUNTS[mountId]", validated_prefix)
        self.assertIn("mount.collected", validated_prefix)

    def test_server_toy_use_validates_collection_and_safe_state_before_casting(self):
        text = read_text(SERVER_LUA)
        handler = function_region(text, "handleToyUse")
        cast_position = handler.index("sender:CastSpell(sender, spellId, false)")
        for token in (
            "local toy = TOYS[toyId]",
            "toy.collected",
            'checkRateLimit(sender, "TOY_USE"',
            "sender:IsDead()",
            "sender:IsOnVehicle()",
            "local spellId = toy.spellId",
        ):
            position = handler.find(token)
            self.assertGreaterEqual(position, 0, f"missing toy guard: {token}")
            self.assertLess(position, cast_position, f"late toy guard: {token}")
        self.assertIn('sendToyUseError(sender, requestId, "CAST_FAILED")', handler)
        self.assertIn("sendToyUseAccepted(sender, requestId, toyId)", handler)

    def test_server_summon_rejects_unsafe_states_before_casting(self):
        text = read_text(SERVER_LUA)
        handler = function_region(text, "handleSummon")
        cast_position = handler.index("sender:CastSpell(sender, spellId, false)")
        for token in (
            "sender:IsDead()",
            "sender:IsInCombat()",
            "sender:IsOnVehicle()",
            "sender:IsFlying()",
        ):
            position = handler.find(token)
            self.assertGreaterEqual(position, 0, f"missing summon guard: {token}")
            self.assertLess(position, cast_position, f"late summon guard: {token}")
        self.assertLess(handler.find("sender:IsMounted()"), cast_position)
        self.assertLess(handler.find("sender:Dismount()"), cast_position)
        self.assertIn("local accepted = pcall(function()", handler)
        self.assertIn('sendSummonError(sender, requestId, "CAST_FAILED")', handler)
        self.assertIn('sendSummonAccepted(sender, requestId, mountId)', handler)

    def test_server_rate_limits_model_and_summon_per_player_without_persistence(self):
        text = read_text(SERVER_LUA)
        limiter = function_region(text, "checkRateLimit")
        for token in (
            "sender:GetGUIDLow()",
            "os.time()",
            "RATE_LIMITS",
            "operation",
            "limit",
        ):
            self.assertIn(token, limiter)
        for function_name, operation in (
            ("handleModel", '"MODEL"'),
            ("handleSummon", '"SUMMON"'),
            ("handlePetModel", '"PET_MODEL"'),
            ("handlePetSummon", '"PET_SUMMON"'),
            ("handleToyUse", '"TOY_USE"'),
        ):
            handler = function_region(text, function_name)
            self.assertIn("checkRateLimit(sender", handler)
            self.assertIn(operation, handler)

    def test_server_bridge_reads_enabled_switch_with_missing_value_defaulting_true(self):
        text = read_text(SERVER_LUA)
        for token in (
            "local function isEnabled(value)",
            'if value == nil or value == "" then',
            "if value == false or value == 0 then",
            'if type(value) == "string" and string.lower(value) == "false" then',
            'local ENABLED = isEnabled(GetConfigValue("SoloCollections.Enabled"))',
        ):
            self.assertIn(token, text)
        self.assertNotIn("local ENABLED = true", text)

    def test_server_accepts_runtime_hook_metadata_without_trusting_wrappers(self):
        """ALE hook metadata varies; authenticate only the exact SC1 payload."""
        text = read_text(SERVER_LUA)
        self.assertIn("if not sender then", text)
        self.assertNotRegex(text, r"target\s*[~=]=\s*sender|sender\s*[~=]=\s*target")
        self.assertNotRegex(text, r"messageType\s*[~=]=")
        self.assertIn(
            "sender:SendAddonMessage(PREFIX, RESPONSE, CHAT_MSG_WHISPER, sender)",
            text,
        )


if __name__ == "__main__":
    unittest.main()
