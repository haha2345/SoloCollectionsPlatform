local statePath = arg and arg[1]
assert(type(statePath) == "string" and statePath ~= "", "CollectionState.lua path is required")

SoloCollections = {
    GeneratedCatalog = {
        metadataVersion = "2026.07.20.1",
        assetPackVersion = "round-two-stage8-weapon-presentation-v2",
        collectionTypes = {
            { typeId = 1, typeKey = "synthetic" },
        },
        typeMappingHashes = {
            synthetic = "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        },
    },
    UI = {},
}

dofile(statePath)

local CS = assert(SoloCollections.CollectionState)
local sent = {}
local nonce = "0123456789abcdef"

CS.SetSender(function(body)
    table.insert(sent, body)
end)
CS.BeginConnect("fedcba9876543210")

assert(CS.HandleMessage(
    "A|1|" .. nonce .. "|42|00000001|2026.07.20.1|round-two-stage8-weapon-presentation-v2|0.2.0-dev|1",
    0
) == "HELLO_ACK")
assert(CS.HandleMessage(
    "M|" .. nonce .. "|1|4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
    0
) == "CATEGORY_MAP")

local payload = "1,2,z,10,1z,2s"
local checksum = CS.adler32Hex(payload)
assert(checksum == "179c036b")
assert(CS.HandleMessage("B|" .. nonce .. "|17|1|2|42|" .. checksum .. "|14", 1))

-- out of order chunks must wait for the complete, canonical payload.
assert(CS.HandleMessage("C|" .. nonce .. "|17|2|10,1z,2s", 1.1))
assert(not CS.IsOwnedByType(1, 1))
assert(CS.HandleMessage("C|" .. nonce .. "|17|1|1,2,z,", 1.2))
assert(CS.HandleMessage("C|" .. nonce .. "|17|1|1,2,z,", 1.3))
assert(CS.HandleMessage("E|" .. nonce .. "|17|" .. checksum, 1.4))
assert(CS.GetState() == "Ready")
assert(CS.GetRevision() == "42")
assert(CS.IsOwnedByType(1, 1))
assert(CS.IsOwnedByType(1, 71))
assert(CS.IsOwnedByType(1, 100))

-- old nonce traffic must be ignored without modifying committed ownership.
assert(CS.HandleMessage("D|0000000000000000|1|43|R|1", 2) == nil)
assert(CS.IsOwnedByType(1, 1))
assert(CS.GetRevision() == "42")

-- conflicting duplicate chunks invalidate only the pending transfer.
local beforeConflict = #sent
assert(CS.HandleMessage("B|" .. nonce .. "|18|1|2|42|" .. checksum .. "|14", 3))
assert(CS.HandleMessage("C|" .. nonce .. "|18|1|1,2,z,", 3.1))
assert(CS.HandleMessage("C|" .. nonce .. "|18|1|1,3,z,", 3.2))
assert(#sent == beforeConflict + 1)
assert(string.find(sent[#sent], "|CHECKSUM_MISMATCH|1|42", 1, true))
assert(CS.IsOwnedByType(1, 1))

-- missing chunks cannot partially replace the last valid snapshot.
assert(CS.HandleMessage("B|" .. nonce .. "|19|1|2|42|" .. checksum .. "|14", 4))
assert(CS.HandleMessage("C|" .. nonce .. "|19|1|1,2,z,", 4.1))
assert(CS.HandleMessage("E|" .. nonce .. "|19|" .. checksum, 4.2))
assert(CS.IsOwnedByType(1, 100))
assert(CS.GetRevision() == "42")

-- revision gap requests a resync and preserves the last committed revision.
local beforeGap = #sent
assert(CS.HandleMessage("D|" .. nonce .. "|1|44|R|1", 5))
assert(#sent == beforeGap + 1)
assert(string.find(sent[#sent], "|REVISION_GAP|1|42", 1, true))
assert(CS.IsOwnedByType(1, 1))
assert(CS.GetRevision() == "42")

assert(CS.HandleMessage("D|" .. nonce .. "|1|43|R|1", 6))
assert(not CS.IsOwnedByType(1, 1))
assert(CS.GetRevision() == "43")

print("SC2 CollectionState Lua harness passed")
