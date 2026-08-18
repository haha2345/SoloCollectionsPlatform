-- DragonUI_NewEra/modules/cooldownviewer/Equip.lua — on-use trinket discovery and the per-item
-- assignment registry. Downport of NewEra/CooldownViewer/CooldownViewerEquip.lua (182 lines).
--
-- THE MODEL (retail PTR 12.1.0 EquipSlotEssential/EquipSlotTracked, which upstream reproduces).
-- An item cooldown does not belong to a viewer by default. It is DISCOVERED, keyed by a stable
-- token, and parked in a source pool — "Equip Active" in the /cdm panel — with no on-screen
-- presence at all. The player drags it into Essential or Utility to make it show. Assignment is
-- persisted per token, so re-equipping the same trinket restores the choice:
--
--   nil                       unassigned — in the source pool, in no viewer (the default)
--   "essential" / "utility"   shown in that cooldown viewer
--   "hidden"                  explicitly removed by the player (NOT the same as unassigned:
--                             an absent key falls back to the class default, a present one never
--                             does, so "hidden" has to be storable)
--
-- WHAT IS PORTED, AND WHAT IS NOT
--
-- Trinkets port exactly, and they cost nothing in curation: GetInventoryItemID gives the item in
-- each trinket slot and GetItemSpell gives its on-use spell. Every id comes from the client at
-- runtime; nothing is typed. That is the whole active-trinket feature.
--
-- CONSUMABLES ARE DEFERRED, and the reason is data, not effort. Upstream's M.POTION_CATEGORIES is
-- a hand-curated table of ~45 VANILLA item ids bucketed into Healing/Mana/Healthstone/Soulstone/
-- Combat, best-rank-first, so the runtime can show ONE slot per bucket for the best item held.
-- WotLK adds a whole tier to every one of those buckets (Runic potions, the Fel/Master healthstone
-- line, Endless-series flasks), and this project's prime directive is that ids come from client
-- data, never from memory. The 3.3.5a client cannot supply them: Item.dbc carries no item names and
-- no item→spell link — both live server-side in item_template — so there is nothing to generate a
-- bucketed list FROM. PORT_PLAN §G.9 scopes the way through (classify at runtime by the use-spell's
-- Spell.dbc effect, which IS client data), and that is a generator pass rather than a paste.
--
-- THE PASSIVE POOL IS CUT, and this is not a scheduling decision. Upstream's GetEquipPassiveItems
-- walks the same two trinket slots and surfaces each one's USE-spell as a trackable aura. So a proc
-- trinket — the only kind for which a passive aura row would mean anything — returns nil from
-- GetItemSpell and never appears; the pool can only ever contain on-use trinkets that are already
-- rows in the active pool. Upstream flags this itself ("Era has no on-equip-aura data layer",
-- TODO(hydrate)). Shipping it here would add a second source section whose contents duplicate the
-- first. The equipPassive category and its half of the legal-target matrix go with it.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

-- Slot ids, from the client's own globals where it defines them. 13/14 is the 3.3.5a literal.
M.TRINKET_SLOTS = { INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14 }

-- ── Assignment registry ─────────────────────────────────────────────────────────────────────────

-- Same accessor shape as CooldownViewer.lua's file-local `store`, which is not exported. Two lines
-- is cheaper than widening that file's surface for one consumer.
local function store(create)
  local cfg = NE.Config and NE.Config()
  if not cfg then return nil end
  if not cfg.cooldownviewer then
    if not create then return nil end
    cfg.cooldownviewer = {}
  end
  return cfg.cooldownviewer
end

-- Per-class defaults ("the Cooldown Manager must include X for this class"). Upstream's only
-- entries are the Warlock's Healthstone and Soulstone, which are potion-category tokens — so this
-- is empty until consumables land, and it stays here so §G.9 is a data change, not a code change.
M.DEFAULT_EQUIP_BY_CLASS = {}

local function defaultEquipAssignment(token)
  if not token then return nil end
  local _, class = UnitClass("player")
  local byClass = class and M.DEFAULT_EQUIP_BY_CLASS[class]
  return byClass and byClass[token] or nil
end

function M.GetEquipAssignment(token)
  if not token then return nil end
  -- Trinket placement is layout, so it follows the talent group like the spell lists do.
  local cd = M._layoutBucket and M._layoutBucket(false)
  local reg = cd and cd.equipAssign
  -- A PRESENT key — including "hidden" — is an explicit choice and wins. Only a genuinely absent
  -- token falls through to the class default, which is what makes "hidden" distinct from unassigned.
  if reg and reg[token] ~= nil then return reg[token] end
  return defaultEquipAssignment(token)
end

function M.SetEquipAssignment(token, cat)
  if not token then return end
  local cd = M._layoutBucket and M._layoutBucket(true)
  if not cd then return end
  cd.equipAssign = cd.equipAssign or {}
  cd.equipAssign[token] = cat        -- nil clears back to the source pool
end

function M.ResetEquipAssignments()
  local cd = M._layoutBucket and M._layoutBucket(true)
  if cd then cd.equipAssign = {} end
end

-- ── Discovery ───────────────────────────────────────────────────────────────────────────────────

-- Every equipped trinket that has an on-use spell. Entries are what the viewer's Rebuild loop and
-- the settings panel both consume:
--   { kind = "active", source = "trinket", token = "item:<itemID>", itemID, spellID, slot, label }
--
-- `label` is the USE-SPELL's name, not the item's — that is what GetItemSpell returns, and it is
-- the more useful of the two on a 38px tile ("Speed" beats "Mirror of Truth"). It can be nil until
-- the server caches the item; GET_ITEM_INFO_RECEIVED re-renders when it lands.
function M.GetEquipActiveItems()
  local out = {}
  if not GetInventoryItemID then return out end
  for _, slot in ipairs(M.TRINKET_SLOTS) do
    local itemID = GetInventoryItemID("player", slot)
    if itemID then
      local name, spellID = M.GetItemUseSpell(itemID)
      if spellID then
        out[#out + 1] = { kind = "active", source = "trinket", token = "item:" .. itemID,
          itemID = itemID, spellID = spellID, slot = slot, label = name }
      end
    end
  end
  return out
end

-- The discovered items assigned to one VIEWER category. Note the argument is a viewer category
-- ("essential" / "utility"), not a settings category id — assignment values are stored in viewer
-- terms so this comparison is direct, and SettingsAdapter maps its own ids onto them.
function M.GetEquipItemsForCategory(cat)
  local out = {}
  if not cat then return out end
  for _, e in ipairs(M.GetEquipActiveItems()) do
    if M.GetEquipAssignment(e.token) == cat then out[#out + 1] = e end
  end
  return out
end
