-- DragonUI_NewEra/modules/character/Sidebar.lua — the collapsible right-side STATS sidebar.
--
-- ARCHITECTURE (CONTRACT_S1 §A0 / VISUAL_SPEC): the sidebar is the signature DF feature. It hosts
-- NE_CharacterStatsPane inside NE.charpanel.InsetRight (209x364, hidden until expanded). Toggling the
-- sidebar open/closed calls NE.charpanel.SetSidebarExpanded(true/false) (foundation, CharacterPanel.lua),
-- which GROWS the frame 338->548 and shows/hides InsetRight. We replace the foundation's SelectSidebar
-- and ReassertLayout stubs.
--
-- WHAT (the DF look) — ported faithfully from NewEra/CharacterPanel/Sidebar.lua: 7 collapsible stat
-- sections (General / Attributes / Melee / Ranged / Spell / Defense / Resistances), 197x40 headers,
-- 187x15 rows with an alternating background, a scrollable pane.
--
-- HOW (proven 3.3.5a mechanics) — lifted from /root/downport/DragonflightUICharacter/StatsPanel.lua,
-- the user's WORKING 3.3.5 stats panel (928 lines). Those are the REAL getters/return-shapes for this
-- client: UnitStat / UnitArmor(base,eff,_,pos,neg) / UnitAttackPower / UnitRangedAttackPower /
-- GetCritChance / UnitResistance / GetCombatRating / GetManaRegen, etc. Every getter is pcall'd; a
-- missing API renders "--" and never errors (CONTRACT §A.5 / §B graceful degradation).
--
-- DOWNPORT/REPORT — PIXEL-SCROLL LAYOUT (faithful NewEra, which used VARIABLE row heights via a retail
-- WowScrollBox absent on 3.3.5a): we build ALL header+stat rows ONCE into a tall content frame at their
-- cumulative Y positions (header 40 + 2 gap, rows 15 each) inside a plain ScrollFrame, and scroll by
-- PIXELS. The custom scrollbar drives the ScrollFrame's SetVerticalScroll via NE.scrollbar.
-- BuildCustomPixel. Collapse-on-header-click hides a section's rows and re-runs the cumulative layout.
-- Shift+left-drag on a header reorders the blocks (see the reorder section); both the collapse state
-- and the block order persist per character in NE.db.charStats.
--
-- 3.3.5 GOTCHAS (§B) applied here:
--   * No SetShown — Show()/Hide() only.
--   * NE.tex.SetAtlas returns false on a missing sheet — the UI-Character-Info-Title atlas isn't
--     shipped on 3.3.5a, so the header falls back to a solid tint (DOWNPORT). The alternating row bg
--     stays a FAINT NEUTRAL tint (user preference — NOT the brown line-bounce atlas).
--   * pcall every stat getter inside the render/tooltip loops.

local NE = DragonUI_NewEra
local L = NE:GetLocale()
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local format, min, max, floor, abs = string.format, math.min, math.max, math.floor, math.abs

-- ----------------------------------------------------------------------------
-- Local logger (mirrors CharacterPanel.lua's). DOWNPORT: NE.Log may be absent standalone.
-- ----------------------------------------------------------------------------
local function log(msg)
  if CP._log then CP._log(msg); return end
  if NE.Log then NE.Log("SIDEBAR", msg); return end
end

local function getLocaleString(global, fallback)
  if type(global) == "string" and global ~= "" then
    local v = _G[global]
    if type(v) == "string" and v ~= "" then
      return v
    end
  end
  if type(L) == "table" and type(fallback) == "string" and fallback ~= "" then
    local rawVal = rawget(L, fallback)
    if type(rawVal) == "string" and rawVal ~= "" then
      return rawVal
    end
    local ok, res = pcall(function() return L[fallback] end)
    if ok and type(res) == "string" and res ~= "" then
      return res
    end
  end
  return fallback
end

if type(L) == "table" then
  local mt = getmetatable(L) or {}
  mt.__call = function(self, global, fallback)
    return getLocaleString(global, fallback)
  end
  setmetatable(L, mt)
else
  L = function(global, fallback)
    return getLocaleString(global, fallback)
  end
end

-- ----------------------------------------------------------------------------
-- Geometry — DOWNPORT/REPORT: faithful NewEra exact dims.
-- ----------------------------------------------------------------------------
local PANE_INSET      = 3      -- NE_CharacterStatsPane sits InsetRight.TOPLEFT(3,-3)/BOTTOMRIGHT(-3,2)
local HEADER_W        = 197    -- NewEra section header 197x40
local HEADER_H        = 40     -- DOWNPORT/REPORT: revert to NewEra's 40 (was 22)
local ROW_W           = 187    -- NewEra stat row 187x15
local ROW_H           = 15
local HEADER_GAP      = 2      -- 2px gap below each header before its first row
local FIRST_ROW_INSET = -5     -- first row after a header: TOPRIGHT(-5,0) (row 187 vs header 197)
local SCROLLBAR_W     = 8      -- custom pixel scrollbar width
local SCROLLBAR_GAP   = SCROLLBAR_W + 2   -- room for the bar on the right of the viewport
-- Item Level block = the 197x40 header box + a strip beneath it for the number (like a stat row).
local ITEMLEVEL_ROW_H = HEADER_H + 22

-- ----------------------------------------------------------------------------
-- Stat formatting helpers (ported from DUIC StatsPanel.lua — the proven 3.3.5 forms).
-- ----------------------------------------------------------------------------
local HL   = HIGHLIGHT_FONT_COLOR_CODE or "|cffffffff"
local GRN  = GREEN_FONT_COLOR_CODE     or "|cff20ff20"
local RED  = RED_FONT_COLOR_CODE       or "|cffff2020"
local CLOSE= FONT_COLOR_CODE_CLOSE     or "|r"

-- Buffed primary-stat formatter (DUIC PaperDollFormatStat): returns colored value + tooltip title.
local function formatStat(name, base, posBuff, negBuff)
  base    = base    or 0
  posBuff = posBuff or 0
  negBuff = negBuff or 0
  local effective = max(0, base + posBuff + negBuff)
  local text = HL .. name .. " " .. effective
  local frameText
  if posBuff == 0 and negBuff == 0 then
    text = text .. CLOSE
    frameText = tostring(effective)
  else
    if posBuff > 0 or negBuff < 0 then text = text .. " (" .. base .. CLOSE end
    if posBuff > 0 then text = text .. CLOSE .. GRN .. "+" .. posBuff .. CLOSE end
    if negBuff < 0 then text = text .. RED .. " " .. negBuff .. CLOSE end
    if posBuff > 0 or negBuff < 0 then text = text .. HL .. ")" .. CLOSE end
    if negBuff < 0 then
      frameText = RED .. effective .. CLOSE
    else
      frameText = GRN .. effective .. CLOSE
    end
  end
  return frameText, text
end

-- Safe combat-rating reads (these globals/funcs exist on 3.3.5 but pcall keeps us bulletproof).
local function rating(cr)
  local ok, v = pcall(GetCombatRating, cr)
  return (ok and v) or 0
end
local function ratingBonus(cr)
  local ok, v = pcall(GetCombatRatingBonus, cr)
  return (ok and v) or 0
end
-- Stock shows melee/ranged haste inside the Attack Speed tooltip (PaperDollFrame_SetAttackSpeed),
-- not as its own row. Mirror that: "Haste rating N (X% haste)".
local function hasteLine(cr)
  return format(_G.CR_HASTE_RATING_TOOLTIP or "Haste rating %d (%.2f%% haste)", rating(cr), ratingBonus(cr))
end

-- Self-contained melee hand maths (DUIC ComputeHand — replaces the retail combat dummy).
local function computeHand(minDamage, maxDamage, physPos, physNeg, percent, speed)
  minDamage = minDamage or 0; maxDamage = maxDamage or 0
  physPos = physPos or 0; physNeg = physNeg or 0; percent = percent or 1
  local displayMin = max(floor(minDamage), 1)
  local displayMax = max(floor(maxDamage), 1)
  local realMin = (minDamage / percent) - physPos - physNeg
  local realMax = (maxDamage / percent) - physPos - physNeg
  local baseDamage = (realMin + realMax) * 0.5
  local fullDamage = (baseDamage + physPos + physNeg) * percent
  local totalBonus = fullDamage - baseDamage
  local dps = (speed and speed > 0) and (max(fullDamage, 1) / speed) or 0
  local dmgText
  if totalBonus == 0 then
    dmgText = displayMin .. " - " .. displayMax
  else
    local color = (totalBonus > 0) and "|cff20ff20" or "|cffff2020"
    dmgText = color .. displayMin .. " - " .. displayMax .. "|r"
  end
  return dmgText, dps
end

-- ----------------------------------------------------------------------------
-- Stat element registry. Each element: { id, name, func() -> (value, tipTitle, tipBody, tipLines) }.
-- Mirrors NewEra's 7-section layout; getters are the DUIC-proven 3.3.5 ones.
-- tipLines (optional) is a { {left=, right=, white=} ... } list for multi-line tooltips.
-- ----------------------------------------------------------------------------
local MAGIC_AP = _G.ATTACK_POWER_MAGIC_NUMBER or 14

-- DOWNPORT/REPORT: IsRangedWeapon() was unreliable (a Hunter with a bow still read N/A). Match the
-- stock PaperDollFrame_SetRangedAttack rule instead: show ranged stats whenever the ranged slot holds
-- an item and the class is NOT a relic user (idol/libram/totem/sigil have no ranged damage).
local function hasRanged()
  local slot = (INVSLOT_RANGED or 18)
  local ok, tex = pcall(function() return GetInventoryItemTexture and GetInventoryItemTexture("player", slot) end)
  if not (ok and tex) then return false end
  local relicOk, relic = pcall(function() return UnitHasRelicSlot and UnitHasRelicSlot("player") end)
  if relicOk and relic then return false end
  return true
end

-- ----------------------------------------------------------------------------
-- Average item level (retail's PaperDollFrame ItemLevelFrame, pinned above the General category).
-- 3.3.5a has no GetAverageItemLevel API, so we compute it ourselves: 17 gear slots (retail's own
-- formula excludes Shirt/Tabard — they don't count), GetInventoryItemLink + GetItemInfo (4th return
-- = itemLevel) per slot, pcall'd — an uncached link just contributes 0 until GetItemInfo caches it,
-- matching how every other stat getter in this file degrades (§B).
-- ----------------------------------------------------------------------------
local ILVL_SLOTS = {
  INVSLOT_HEAD or 1, INVSLOT_NECK or 2, INVSLOT_SHOULDER or 3, INVSLOT_BACK or 15,
  INVSLOT_CHEST or 5, INVSLOT_WRIST or 9, INVSLOT_HAND or 10, INVSLOT_WAIST or 6,
  INVSLOT_LEGS or 7, INVSLOT_FEET or 8, INVSLOT_FINGER1 or 11, INVSLOT_FINGER2 or 12,
  INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14, INVSLOT_MAINHAND or 16,
  INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18,
}

-- Average item level across those 17 slots (empty slots count as 0, matching retail's formula), plus
-- the average QUALITY of the slots that ARE filled — retail colors the number by an ilvl/content
-- tier we have no data for on 3.3.5a, so we approximate with the standard item-quality palette
-- instead (ITEM_QUALITY_COLORS, the same table item borders/links use everywhere else in the client).
local function averageItemLevel()
  local total, qTotal, qCount = 0, 0, 0
  for _, slotId in ipairs(ILVL_SLOTS) do
    local link = GetInventoryItemLink("player", slotId)
    if link then
      local ok, _, _, quality, ilvl = pcall(GetItemInfo, link)
      if ok then
        if ilvl then total = total + ilvl end
        if quality then qTotal = qTotal + quality; qCount = qCount + 1 end
      end
    end
  end
  local avgIlvl = total / #ILVL_SLOTS
  local avgQuality = (qCount > 0) and floor(qTotal / qCount + 0.5) or nil
  return avgIlvl, avgQuality
end

-- ----------------------------------------------------------------------------
-- Movement speed, as a percentage of normal running speed (retail's convention: 100% = base run,
-- epic ground mount 200%, epic flight 380%).
--
-- DOWNPORT: 3.3.5a exposes ONLY `GetUnitSpeed(unit)` -> the unit's CURRENT speed in yards/second.
-- Retail's 4-return form (currentSpeed, runSpeed, flightSpeed, swimSpeed) that PaperDollFrame's own
-- movement-speed stat reads is Cata+, so there is no way to ask this client "what WOULD my run speed
-- be" — standing at the character sheet genuinely reads 0.
--
-- So we sample while moving, tagged with the movement CONTEXT the sample was taken in (mounted /
-- flying / swimming / shapeshift form), and report the fastest RECENT sample for the current context.
-- Deliberately NOT the live reading: walking is a flat 2.5 yd/s (36%) and backpedalling 4.5 (64%),
-- and this row answers "what is my movement speed stat" — 100 / 120 / 80 — not "how fast am I
-- physically travelling this instant". Walk-speed samples are dropped outright (WALK_FLOOR) and
-- taking the max means backpedalling can't pull the figure down while you're also moving forward.
-- Mount up and the on-foot 100% isn't shown as if it were current — samples are per context.
-- With no sample at all we assume 100%: normal run speed is the right default, and it self-corrects
-- on your first step.
-- ----------------------------------------------------------------------------
local BASE_SPEED   = 7     -- yards/second at 100%. DOWNPORT: BASE_MOVEMENT_SPEED is Cata+.
local SPEED_ID     = "movespeed"
-- Walking is a flat 2.5 yd/s (36%). Below this we assume walking rather than a slow effect: the
-- slowest real snares land around 50-60%, and a full root reports speed 0 (never sampled at all).
local WALK_FLOOR   = 40
-- Seconds after which a stored measurement stops outranking a newer, slower one. This is what lets
-- an expired Sprint decay back to 100% WITHOUT invalidating on UNIT_AURA — an aura-driven reset
-- fires constantly in combat and would leave the row bouncing to whatever you did in the instant
-- after each proc, backpedalling included.
local SPEED_WINDOW = 6
local speedSamples = {}    -- movement context -> { pct = fastest % measured, t = when }

local function speedContext()
  local form = (GetShapeshiftForm and GetShapeshiftForm()) or 0
  return format("%d-%d-%d-%d",
    IsMounted  and IsMounted()  and 1 or 0,
    IsFlying   and IsFlying()   and 1 or 0,
    IsSwimming and IsSwimming() and 1 or 0,
    tonumber(form) or 0)
end

-- Returns percent-of-base, measured. measured=false means nothing has been sampled in this context
-- yet and the 100% baseline is being assumed.
-- Samples are kept PER context rather than in one slot, so dismounting restores the on-foot figure
-- immediately instead of falling back to the assumed baseline until you take another step.
local function movementSpeedPct()
  local cur = (GetUnitSpeed and GetUnitSpeed("player")) or 0
  local ctx = speedContext()
  local pct = cur / BASE_SPEED * 100
  if pct >= WALK_FLOOR then
    local now  = (GetTime and GetTime()) or 0
    local best = speedSamples[ctx]
    -- Take the sample if it's faster, or if what we're holding has gone stale (a buff that expired).
    if not best or pct >= best.pct or (now - best.t) > SPEED_WINDOW then
      speedSamples[ctx] = { pct = pct, t = now }
    end
  end
  local best = speedSamples[ctx]
  if best then return best.pct, true end
  return 100, false
end

local function movementSpeedText()
  return format("%d%%", floor(movementSpeedPct() + 0.5))
end

-- ----------------------------------------------------------------------------
-- Equipment durability as a percentage: total current / total maximum across everything equipped.
-- GetInventoryItemDurability returns nil for items with no durability at all (rings, neck, trinkets,
-- shirt, tabard, and heirlooms) — those must be SKIPPED, not counted as 0, or a fully-kitted
-- character would read far below its real condition. Nothing durable equipped -> nil -> "--".
-- Also reports the single worst-condition slot, which is the number that actually matters (an
-- average of 90% still means something is about to break at 5%).
-- ----------------------------------------------------------------------------
local function equipmentDurability()
  local cur, maxTotal, worst = 0, 0, nil
  for slot = 1, 19 do   -- INVSLOT_HEAD .. INVSLOT_TABARD; non-durable slots return nil and are skipped
    local ok, c, m = pcall(GetInventoryItemDurability, slot)
    if ok and c and m and m > 0 then
      cur, maxTotal = cur + c, maxTotal + m
      local pct = c / m * 100
      if not worst or pct < worst then worst = pct end
    end
  end
  if maxTotal == 0 then return nil end
  return cur / maxTotal * 100, cur, maxTotal, worst
end

-- 7 sections, in the locked NewEra order. Each `stats` is a list of element defs.
local SECTIONS = {
  {
    id = "general", title = L("STAT_CATEGORY_GENERAL", L("GENERAL", "General")),
    stats = {
      { id = "health", name = L("HEALTH", "Health"), func = function()
          local hp = UnitHealthMax("player") or 0
          return tostring(hp), (L("HEALTH", "Health") .. " " .. hp),
				L("MAX_HEALTH_TOOLTIP", "Maximum Health. If your health reaches zero, you will die.")
        end },
      { id = "power", name = (function()
          local _, token = UnitPowerType("player")
          return (token and _G[token]) or L("MANA", "Mana")
        end)(), func = function()
          local pmax = UnitPowerMax("player") or 0
          local _, token = UnitPowerType("player")
          local plabel = (token and _G[token]) or L("MANA", "Mana")
          return tostring(pmax), (plabel .. " " .. pmax),
                 format(L["Your maximum %s."], plabel)
        end },
      { id = SPEED_ID, name = L("STAT_MOVEMENT_SPEED", "Movement Speed"), func = function()
          local label = L("STAT_MOVEMENT_SPEED", "Movement Speed")
          local pct, measured = movementSpeedPct()
          local val = format("%d%%", floor(pct + 0.5))
          return val, (label .. " " .. val), format(
            "Your running speed. 100%% is normal (%d yards/second); mounts and speed effects raise it,"
            .. " slows lower it. Walking and backpedalling are ignored."
            .. (measured and "" or "\nAssuming the 100%% baseline — move a step to measure it."),
            BASE_SPEED)
        end },
      { id = "durability", name = L("DURABILITY", "Durability"), func = function()
          local label = L("DURABILITY", "Durability")
          local pct, cur, maxTotal, worst = equipmentDurability()
          if not pct then
            return "--", label, "You have nothing equipped that can take durability damage."
          end
          local val = format("%d%%", floor(pct + 0.5))
          return val, (label .. " " .. val), format(
            "Condition of your equipment: %d of %d durability across every equipped item that has it."
            .. "\nWorst slot: %d%%."
            .. "\nItems with no durability (rings, neck, trinkets, shirt, tabard) are not counted.",
            cur, maxTotal, floor(worst + 0.5))
        end },
    },
  },

  {
    id = "attributes", title = L("STAT_CATEGORY_ATTRIBUTES", "Attributes"),
    stats = (function()
      -- DOWNPORT/REPORT: the stock DEFAULT_STATi_TOOLTIP globals are FORMAT strings ("Increases Mana
      -- by %d\nIncreases Spell Critical Hit by %.2f%%") whose placeholders need per-class computed
      -- values we don't have here — passed through raw they printed literal "%d"/"%.2f%%". Use accurate
      -- static descriptions instead so the tooltip body is correct with no unfilled placeholders.
      local ATTR_DESC = {
        "Increases attack power for some classes and the damage you block with a shield.",
        "Increases critical strike chance, dodge chance, armor, and (for some classes) attack power.",
        "Increases your maximum health.",
        "Increases your maximum mana and your spell critical strike chance.",
        "Increases your health and mana regeneration while out of combat.",
      }
      local t = {}
      for i = 1, 5 do
        local statName = _G["SPELL_STAT" .. i .. "_NAME"] or ("Stat" .. i)
        t[i] = {
          id = "stat" .. i, name = statName,
          func = function()
            local base, eff, posBuff, negBuff = UnitStat("player", i)
            local frameText, tip = formatStat(statName, base, posBuff, negBuff)
            return frameText, tip, L(ATTR_DESC[i], ATTR_DESC[i])
          end,
        }
      end
      return t
    end)(),
  },

  {
    id = "melee", title = L("MELEE", "Melee"),
    stats = {
      { id = "mh_damage", name = L("DAMAGE", "Damage"), func = function()
          local speed, offSpeed = UnitAttackSpeed("player")
          local minD, maxD, minO, maxO, physPos, physNeg, percent = UnitDamage("player")
          local mhText, mhDps = computeHand(minD, maxD, physPos, physNeg, percent, speed)
          local lines = {
            { left = L("INVTYPE_WEAPONMAINHAND", "Main Hand") },
            { left = L("ATTACK_SPEED_SECONDS", "Speed"), right = format("%.2f", speed or 0) },
            { left = L("DAMAGE", "Damage"), right = mhText },
            { left = L("DAMAGE_PER_SECOND", "DPS"), right = format("%.1f", mhDps) },
          }
          if offSpeed then
            local ohText, ohDps = computeHand(minO, maxO, physPos, physNeg, percent, offSpeed)
            lines[#lines + 1] = { left = " " }
            lines[#lines + 1] = { left = L("INVTYPE_WEAPONOFFHAND", "Off Hand"), white = true }
            lines[#lines + 1] = { left = L("ATTACK_SPEED_SECONDS", "Speed"), right = format("%.2f", offSpeed) }
            lines[#lines + 1] = { left = L("DAMAGE", "Damage"), right = ohText }
            lines[#lines + 1] = { left = L("DAMAGE_PER_SECOND", "DPS"), right = format("%.1f", ohDps) }
          end
          return mhText, nil, nil, lines
        end },
      { id = "mh_dps", name = L("STAT_DPS_SHORT", "DPS"), func = function()
          local speed, offSpeed = UnitAttackSpeed("player")
          local minD, maxD, minO, maxO, physPos, physNeg, percent = UnitDamage("player")
          local _, mhDps = computeHand(minD, maxD, physPos, physNeg, percent, speed)
          local frameText = format("%.1f", mhDps)
          local lines = { { left = L("DAMAGE_PER_SECOND", "Damage Per Second") },
                          { left = L("INVTYPE_WEAPONMAINHAND", "Main Hand"), right = frameText } }
          if offSpeed then
            local _, ohDps = computeHand(minO, maxO, physPos, physNeg, percent, offSpeed)
            lines[#lines + 1] = { left = L("INVTYPE_WEAPONOFFHAND", "Off Hand"), right = format("%.1f", ohDps) }
          end
          return frameText, nil, nil, lines
        end },
      { id = "ap", name = L("ATTACK_POWER", "Attack Power"), func = function()
          local base, posBuff, negBuff = UnitAttackPower("player")
          local frameText, tip = formatStat(L("MELEE_ATTACK_POWER", "Attack Power"), base, posBuff, negBuff)
          local body = format(L("MELEE_ATTACK_POWER_TOOLTIP",
            "Increases your damage with melee weapons by %.1f damage per second."),
            max((base or 0) + (posBuff or 0) + (negBuff or 0), 0) / MAGIC_AP)
          return frameText, tip, body
        end },
      { id = "attackspeed", name = L("ATTACK_SPEED", "Attack Speed"), func = function()
          local speed, offSpeed = UnitAttackSpeed("player")
          local frameText = format("%.2f", speed or 0)
          if offSpeed then frameText = frameText .. " / " .. format("%.2f", offSpeed) end
          return frameText, (L("ATTACK_SPEED", "Attack Speed") .. " " .. frameText),
				L("Seconds between melee swings.", "Seconds between melee swings.") .. "\n" .. hasteLine(CR_HASTE_MELEE or 18)
        end },
      { id = "hit", name = L("COMBAT_RATING_NAME6", "Hit Rating"), func = function()
          local r = rating(CR_HIT_MELEE)
          return tostring(r), (L("COMBAT_RATING_NAME6", "Hit") .. " " .. r),
                 format(L["Improves your chance to hit by %.2f%%."], ratingBonus(CR_HIT_MELEE))
        end },
      { id = "crit", name = L("MELEE_CRIT_CHANCE", "Crit Chance"), func = function()
          local crit = (GetCritChance and GetCritChance()) or 0
          local str = format("%.2f%%", crit)
          return str, (L("MELEE_CRIT_CHANCE", "Crit Chance") .. " " .. str),
                 L["Chance of melee attacks dealing extra damage."]
        end },
      { id = "arp", name = L["Armor Penetration"], func = function()
		local r = rating(CR_ARMOR_PENETRATION)
		local ok, pct = pcall(GetArmorPenetration)
		return tostring(r), (L["Armor Penetration"] .. " " .. r),
           format(L["Reduces the target's armor by up to %.2f%%."], (ok and pct) or 0)
		end },
      { id = "expertise", name = L("STAT_EXPERTISE", "Expertise"), func = function()
          local ok, exp, offExp = pcall(GetExpertise)
          if not ok then return "--" end
          local speed, offSpeed = UnitAttackSpeed("player")
          local r = offSpeed and (exp .. " / " .. (offExp or 0)) or tostring(exp)
          return r, (L("STAT_EXPERTISE", "Expertise") .. " " .. r),
                 L["Reduces the chance your attacks are dodged or parried."]
        end },
    },
  },

  {
    id = "ranged", title = L("RANGED", "Ranged"),
    stats = {
      { id = "r_damage", name = L("DAMAGE", "Damage"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          local speed, lowD, hiD = UnitRangedDamage("player")
          local lo = max(floor(lowD or 0), 1)
          local hi = max(floor(hiD or 0), 1)
          local txt = lo .. " - " .. hi
          local dps = (speed and speed > 0) and (((lowD or 0) + (hiD or 0)) / 2 / speed) or 0
          local lines = {
            { left = L("RANGED", "Ranged") },
            { left = L("ATTACK_SPEED_SECONDS", "Speed"), right = format("%.2f", speed or 0) },
            { left = L("DAMAGE", "Damage"), right = txt },
            { left = L("DAMAGE_PER_SECOND", "DPS"), right = format("%.1f", dps) },
          }
          return txt, nil, nil, lines
        end },
      { id = "r_dps", name = L("STAT_DPS_SHORT", "DPS"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          local speed, lowD, hiD = UnitRangedDamage("player")
          local dps = (speed and speed > 0) and (((lowD or 0) + (hiD or 0)) / 2 / speed) or 0
          return format("%.1f", dps)
        end },
      { id = "r_ap", name = L("ATTACK_POWER", "Attack Power"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          if HasWandEquipped and HasWandEquipped() then return L("NOT_APPLICABLE", "N/A") end
          local base, posBuff, negBuff = UnitRangedAttackPower("player")
          local frameText, tip = formatStat(L("RANGED_ATTACK_POWER", "Ranged Attack Power"), base, posBuff, negBuff)
          local body = format(L("RANGED_ATTACK_POWER_TOOLTIP",
            "Increases your damage with ranged weapons by %.1f damage per second."),
            max((base or 0) + (posBuff or 0) + (negBuff or 0), 0) / MAGIC_AP)
          return frameText, tip, body
        end },
      { id = "r_speed", name = L("ATTACK_SPEED", "Attack Speed"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          local speed = UnitRangedDamage("player")
          local ft = format("%.2f", speed or 0)
          return ft, (L("ATTACK_SPEED", "Attack Speed") .. " " .. ft),
                 hasteLine(CR_HASTE_RANGED or 19)
        end },
      { id = "r_hit", name = L("STAT_HIT_CHANCE", "Hit Chance"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          local hit = (GetHitModifier and GetHitModifier()) or 0
          return format("%.2f%%", hit), L("STAT_HIT_CHANCE", "Hit Chance"), L["Reduces your chance to miss."]
        end },
      { id = "r_crit", name = L("STAT_CRITICAL_STRIKE", "Crit Chance"), func = function()
          if not hasRanged() then return L("NOT_APPLICABLE", "N/A") end
          local crit = (GetRangedCritChance and GetRangedCritChance()) or 0
          return format("%.2f%%", crit), (L("CRIT_CHANCE", "Crit Chance") .. format(" %.2f%%", crit)),
                 L["Chance of ranged attacks dealing extra damage."]
        end },
    },
  },

  {
    id = "spell", title = L("STAT_CATEGORY_SPELL", L("MAGIC_SCHOOLS", "Spell")),
    stats = {
      { id = "s_damage", name = L("BONUS_DAMAGE", "Spell Power"), func = function()
          local holy = 2
          local minMod = (GetSpellBonusDamage and GetSpellBonusDamage(holy)) or 0
          local maxSchool = MAX_SPELL_SCHOOLS or 7
          for i = holy + 1, maxSchool do
            local b = (GetSpellBonusDamage and GetSpellBonusDamage(i)) or 0
            minMod = min(minMod, b)
          end
          return tostring(minMod), (L("BONUS_DAMAGE", "Spell Power") .. " " .. minMod),
                 L["Lowest bonus damage across schools. Hover the paper-doll stat for a breakdown."]
        end },
      { id = "s_healing", name = L("BONUS_HEALING", "Bonus Healing"), func = function()
          local heal = (GetSpellBonusHealing and GetSpellBonusHealing()) or 0
          return format(" %d", heal), (L("BONUS_HEALING", "Bonus Healing") .. " " .. heal),
                 L["Bonus power applied to healing spells."]
        end },
      { id = "s_hit", name = L("COMBAT_RATING_NAME8", "Spell Hit"), func = function()
          local r = rating(CR_HIT_SPELL)
          local pen = (GetSpellPenetration and GetSpellPenetration()) or 0
          -- Faithful to the stock Spell Hit tooltip (PaperDollFrame.lua:342, issue #11): the spell
          -- penetration line always shows, even at 0. Reuse Blizzard's own localized format string
          -- when present so the text is byte-identical to default; fall back to a literal otherwise.
          local fmt = _G.CR_HIT_SPELL_TOOLTIP
          local body
          if type(fmt) == "string" then
            body = format(fmt, UnitLevel("player") or 0, ratingBonus(CR_HIT_SPELL), pen, pen)
          else
            body = format("Improves your chance to hit with spells by %.2f%%.\n\nSpell Penetration %d (Reduces enemy resistances by %d)",
                          ratingBonus(CR_HIT_SPELL), pen, pen)
          end
          return tostring(r), (L("COMBAT_RATING_NAME8", "Spell Hit") .. " " .. r), body
        end },
      { id = "s_regen", name = L("MANA_REGEN", "Mana Regen"), func = function()
          if not (UnitHasMana and UnitHasMana("player")) then return L("NOT_APPLICABLE", "N/A") end
          local ok, base, casting = pcall(GetManaRegen)
          if not ok then return "--" end
          base    = floor((base or 0) * 5.0)
          casting = floor((casting or 0) * 5.0)
          return tostring(base), (L("MANA_REGEN", "Mana Regen") .. " " .. base),
                 format(L["Not casting: %d / 5s\nWhile casting: %d / 5s"], base, casting)
        end },
      { id = "s_crit", name = L("SPELL_CRIT_CHANCE", "Spell Crit"), func = function()
          local holy = 2
          local minCrit = (GetSpellCritChance and GetSpellCritChance(holy)) or 0
          local maxSchool = MAX_SPELL_SCHOOLS or 7
          for i = holy + 1, maxSchool do
            local c = (GetSpellCritChance and GetSpellCritChance(i)) or 0
            minCrit = min(minCrit, c)
          end
          local str = format("%.2f%%", minCrit)
          return str, (L("SPELL_CRIT_CHANCE", "Spell Crit") .. " " .. str),
                 L["Chance of spells dealing extra damage."]
        end },
      { id = "s_haste", name = L["Haste Rating"], func = function()
          local cr = CR_HASTE_SPELL or 20
          local r = rating(cr)
          return tostring(r), (L["Haste Rating"] .. " " .. r),
                 format(_G.SPELL_HASTE_TOOLTIP or "Increases the speed that your spells cast by %.2f%%.", ratingBonus(cr))
        end },
    },
  },

  {
    id = "defense", title = L("DEFENSE", "Defense"),
    stats = {
      { id = "armor", name = L("ARMOR", "Armor"), func = function()
          local base, eff, _, posBuff, negBuff = UnitArmor("player")
          local frameText, tip = formatStat(L("ARMOR", "Armor"), base, posBuff, negBuff)
          local body
          if PaperDollFrame_GetArmorReduction then
            local ok, reduction = pcall(PaperDollFrame_GetArmorReduction, eff, UnitLevel("player"))
            if ok and DEFAULT_STATARMOR_TOOLTIP then body = format(DEFAULT_STATARMOR_TOOLTIP, reduction) end
          end
          return frameText, tip, body
        end },
      { id = "defense", name = L("DEFENSE", "Defense"), func = function()
          local base, modifier = 0, 0
          if UnitDefense then base, modifier = UnitDefense("player") end
          base = base or 0; modifier = modifier or 0
          local posBuff = modifier > 0 and modifier or 0
          local negBuff = modifier < 0 and modifier or 0
          local frameText, tip = formatStat(L("DEFENSE", "Defense"), base, posBuff, negBuff)
          return frameText, tip, L["Reduces chance to be hit and crit; raises block/dodge/parry."]
        end },
      { id = "dodge", name = L("DODGE", "Dodge"), func = function()
          local v = (GetDodgeChance and GetDodgeChance()) or 0
          local str = format(" %.2f%%", v)
          return str, (L("DODGE_CHANCE", "Dodge Chance") .. str), L["Chance to dodge enemy melee attacks."]
        end },
      { id = "parry", name = L("PARRY", "Parry"), func = function()
          local v = (GetParryChance and GetParryChance()) or 0
          local str = format(" %.2f%%", v)
          return str, (L("PARRY_CHANCE", "Parry Chance") .. str), L["Chance to parry. Requires a weapon."]
        end },
      { id = "block", name = L("BLOCK", "Block"), func = function()
          local v = (GetBlockChance and GetBlockChance()) or 0
          local str = format(" %.2f%%", v)
          local blockVal = (GetShieldBlock and GetShieldBlock()) or 0
          return str, (L("BLOCK_CHANCE", "Block Chance") .. str),
                 format(L["Chance to block. Requires a shield.\nBlock Value: %d"], blockVal)
        end },
      { id = "resilience", name = L["Resilience"], func = function()
		local cr = CR_CRIT_TAKEN_MELEE or 15   -- resilience rating (drives all three crit-taken schools)
		local r = rating(cr)
		return tostring(r), (L["Resilience"] .. " " .. r),
				format(L["Reduces the chance you'll be critically hit by %.2f%% and reduces critical damage taken."],
                  ratingBonus(cr))
		end },
    },
  },

  {
    id = "resistance", title = L("RESISTANCE", "Resistances"),
    -- Player magic-resist schools (UnitResistance indices): Fire=2, Nature=3, Frost=4, Shadow=5, Arcane=6.
    stats = (function()
      local order = { 2, 3, 4, 6, 5 }   -- Fire, Nature, Frost, Arcane, Shadow (NewEra Arcane-then-Fire reordered for player set)
      local set = { 6, 2, 3, 4, 5 }     -- Arcane, Fire, Nature, Frost, Shadow (NewEra RESIST_SCHOOLS order)
      local t = {}
      for k, i in ipairs(set) do
        local schoolName = _G["RESISTANCE" .. i .. "_NAME"] or ("Resist" .. i)
        t[k] = {
          id = "res" .. i, name = schoolName,
          func = function()
            local base, total, positive, negative = UnitResistance("player", i)
            base = base or 0; total = total or base
            positive = positive or 0; negative = negative or 0
            local frameText
            if abs(negative) > positive then
              frameText = RED .. total .. CLOSE
            elseif abs(negative) == positive then
              frameText = tostring(total)
            else
              frameText = GRN .. total .. CLOSE
            end
            local tip = schoolName .. " " .. total
            if positive ~= 0 or negative ~= 0 then
              tip = tip .. " (" .. base
              if positive > 0 then tip = tip .. GRN .. " +" .. positive .. CLOSE end
              if negative < 0 then tip = tip .. RED .. " " .. negative .. CLOSE end
              tip = tip .. ")"
            end
            return frameText, tip, (L("RESISTANCE_TOOLTIP_DESC", "Reduces magic damage taken."))
          end,
        }
      end
      return t
    end)(),
  },
}

-- ----------------------------------------------------------------------------
-- DOWNPORT/REPORT: PET stat sections — the sidebar can render PET stats instead of the player's
-- when pet mode is active (CP.ExpandPetSidebar). Faithful to NewEra/PetPaperDoll.lua's
-- NE_PetStatsPane: General / Attributes / Attack / Defense / Resistances, read off unit "pet".
-- Every getter pcall-guarded → "--" on a miss or no-pet (CONTRACT §B). Hunter pets get a
-- Training-Points row; warlock minions omit it.
-- ----------------------------------------------------------------------------
local function petIsHunter()
  local ok, _, classFile = pcall(UnitClass, "player")
  return ok and classFile == "HUNTER"
end

local function petPower()
  local _, token = UnitPowerType("pet")
  return (token and _G[token]) or L("MANA", "Mana")
end

local PET_SECTIONS = {
  {
    id = "pet_general", title = L("STAT_CATEGORY_GENERAL", L("GENERAL", "General")),
    stats = (function()
      local t = {
        { id = "pet_health", name = L("HEALTH", "Health"), func = function()
            local v = UnitHealthMax("pet") or 0
            return tostring(v), (L("HEALTH", "Health") .. " " .. v), "Your pet's maximum health."
          end },
        { id = "pet_power", name = L("MANA", "Mana"),
          relabel = petPower,
          func = function()
            local v = UnitPowerMax("pet") or 0
            return tostring(v), (petPower() .. " " .. v), nil
          end },
      }
      -- Hunter pets earn training points (warlock minions return nil → "--"). Built once, so we always
      -- include the row and let the guarded getter degrade rather than gate on class at file-load time
      -- (UnitClass is nil that early).
      t[#t + 1] = { id = "pet_training", name = L("PET_TRAIN_BUTTON", "Training Points"),
        func = function()
          if not petIsHunter() then return L("NOT_APPLICABLE", "N/A") end
          local total, spent = GetPetTrainingPoints()
          total, spent = total or 0, spent or 0
          local unspent = total - spent
          return tostring(unspent),
                 (L("PET_TRAIN_BUTTON", "Training Points") .. ": " .. unspent),
                 format("Total: %d\nSpent: %d", total, spent)
        end }
      return t
    end)(),
  },
  {
    id = "pet_attributes", title = L("STAT_CATEGORY_ATTRIBUTES", "Attributes"),
    stats = (function()
      local t = {}
      for i = 1, 5 do
        local statName = _G["SPELL_STAT" .. i .. "_NAME"] or ("Stat" .. i)
        t[i] = { id = "pet_stat" .. i, name = statName, func = function()
            local _, effective = UnitStat("pet", i)
            effective = effective or 0
            return tostring(effective), (statName .. " " .. effective), nil
          end }
      end
      return t
    end)(),
  },
  {
    id = "pet_attack", title = L("MELEE", L("ATTACK", "Attack")),
    stats = {
      { id = "pet_damage", name = L("DAMAGE", "Damage"), func = function()
          local minD, maxD = UnitDamage("pet")
          local low  = max(floor(minD or 0), 1)
          local high = max(floor(maxD or 0), 1)
          local v = low .. " - " .. high
          return v, (L("DAMAGE", "Damage") .. " " .. v), nil
        end },
      { id = "pet_ap", name = L("ATTACK_POWER", "Attack Power"), func = function()
          local base, pos, neg = UnitAttackPower("pet")
          local eff = (base or 0) + (pos or 0) + (neg or 0)
          return tostring(eff), (L("ATTACK_POWER", "Attack Power") .. " " .. eff), nil
        end },
      { id = "pet_aspeed", name = L("ATTACK_SPEED", "Attack Speed"), func = function()
          local speed = UnitAttackSpeed("pet") or 0
          local v = format("%.2f", speed)
          return v, (L("ATTACK_SPEED", "Attack Speed") .. " " .. v), nil
        end },
    },
  },
  {
    id = "pet_defense", title = L("DEFENSE", "Defense"),
    stats = {
      { id = "pet_armor", name = L("ARMOR", "Armor"), func = function()
          local _, eff = UnitArmor("pet")
          eff = floor(eff or 0)
          return tostring(eff), (L("ARMOR", "Armor") .. " " .. eff), nil
        end },
    },
  },
  {
    id = "pet_resistance", title = L("RESISTANCE", "Resistances"),
    stats = (function()
      local set = { 6, 2, 3, 4, 5 }   -- Arcane, Fire, Nature, Frost, Shadow
      local t = {}
      for k, i in ipairs(set) do
        local schoolName = _G["RESISTANCE" .. i .. "_NAME"] or ("Resist" .. i)
        t[k] = { id = "pet_res" .. i, name = schoolName, func = function()
            local _, total = UnitResistance("pet", i)
            total = total or 0
            return tostring(total), (schoolName .. " " .. total),
                   ("Reduces " .. schoolName:lower() .. " damage taken.")
          end }
      end
      return t
    end)(),
  },
}

-- DOWNPORT/REPORT: the active section set — player sections by default, pet sections in pet mode.
local function activeSections()
  return CP._sidebarPetMode and PET_SECTIONS or SECTIONS
end

-- The Item Level block isn't a SECTIONS entry (it's built separately), but it IS a reorderable
-- block, so it needs an id that lives in the same namespace as the section ids.
local ITEMLEVEL_ID = "itemlevel"

-- ----------------------------------------------------------------------------
-- Collapse state (defaults: General collapsed, the rest expanded — NewEra/DUIC default).
-- ----------------------------------------------------------------------------
local sectionExpanded = {
  -- itemlevel isn't a SECTIONS entry (it's built separately), but it lives in this table so it
  -- collapses like every other header AND rides the same per-character persistence.
  itemlevel = true,
  general = false, attributes = true, melee = true, ranged = true,
  spell = true, defense = true, resistance = true,
  -- Pet sections default all-expanded.
  pet_general = true, pet_attributes = true, pet_attack = true,
  pet_defense = true, pet_resistance = true,
}

-- ----------------------------------------------------------------------------
-- Block ORDER (shift+drag reorder). The sidebar lays blocks out in this order instead of the
-- hardcoded SECTIONS order, so Item Level can be dragged to the bottom, Defense above Melee, etc.
-- Player mode and pet mode keep separate orders (their block sets don't overlap).
-- ----------------------------------------------------------------------------
local blockOrder = { player = nil, pet = nil }   -- id arrays; built lazily, overwritten on DB load

local function defaultOrderFor(petMode)
  local t = {}
  if petMode then
    for _, s in ipairs(PET_SECTIONS) do t[#t + 1] = s.id end
  else
    t[1] = ITEMLEVEL_ID   -- retail pins Item Level at the top; that's only the DEFAULT now
    for _, s in ipairs(SECTIONS) do t[#t + 1] = s.id end
  end
  return t
end

-- A saved order is untrusted: it can hold ids from an older addon version, duplicates, or be missing
-- blocks added since. Keep the valid saved ids in their saved order, then splice any missing block
-- back in at its default index, so a new section appears where it was designed to instead of last.
local function sanitizeOrder(saved, default)
  local valid, seen, out = {}, {}, {}
  for _, id in ipairs(default) do valid[id] = true end
  if type(saved) == "table" then
    for _, id in ipairs(saved) do
      if valid[id] and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
  end
  for i, id in ipairs(default) do
    if not seen[id] then
      seen[id] = true
      tinsert(out, i <= #out + 1 and i or #out + 1, id)
    end
  end
  return out
end

-- The order array for the mode that's showing now (lazily seeded with the defaults pre-DB).
local function currentOrder()
  local key = CP._sidebarPetMode and "pet" or "player"
  if not blockOrder[key] then blockOrder[key] = defaultOrderFor(key == "pet") end
  return blockOrder[key]
end

-- Persist the section collapse state + block order PER CHARACTER (NE.db.charStats[charKey]). The
-- defaults above hold until a saved state is loaded (once NE.db is ready); every header toggle and
-- every completed reorder drag writes it back — so a /reload restores each section's open/closed
-- state AND the block order for that character.
local _stateLoaded = false
local function statsStore(create)
  if not (NE.db and NE.CharKey) then return nil end
  if create then
    NE.db.charStats = NE.db.charStats or {}
    local key = NE.CharKey()
    NE.db.charStats[key] = NE.db.charStats[key] or {}
    return NE.db.charStats[key]
  end
  return NE.db.charStats and NE.db.charStats[NE.CharKey()]
end
local function loadSectionState()
  if _stateLoaded then return end
  -- Need the DB AND a real character name (CharKey is "?-realm" before PLAYER_LOGIN); retry next layout.
  if not (NE.db and NE.CharKey and UnitName and UnitName("player")) then return end
  _stateLoaded = true
  local store = statsStore(false)
  if store then
    -- Collapse flags are stored as bare id->bool at the top level, so skip the two ORDER keys
    -- (they're arrays, and sectionExpanded has no entry for them — the nil check already does it).
    for id, v in pairs(store) do
      if sectionExpanded[id] ~= nil then sectionExpanded[id] = v and true or false end
    end
  end
  blockOrder.player = sanitizeOrder(store and store.sectionOrder, defaultOrderFor(false))
  blockOrder.pet    = sanitizeOrder(store and store.petSectionOrder, defaultOrderFor(true))
end
local function saveSectionState()
  local store = statsStore(true)
  if not store then return end
  for id, v in pairs(sectionExpanded) do store[id] = v and true or false end
  store.sectionOrder    = blockOrder.player or defaultOrderFor(false)
  store.petSectionOrder = blockOrder.pet    or defaultOrderFor(true)
end

-- ----------------------------------------------------------------------------
-- SHIFT + LEFT-DRAG a category header (or the Item Level header) to reorder the blocks.
--
-- The dragged block is NOT detached to follow the cursor — the content frame is a ScrollFrame child
-- and a detached header would be clipped at the pane edge. Instead the list REFLOWS underneath the
-- cursor: the dragged header dims, and whenever the cursor crosses the midpoint of the neighbouring
-- block, the two swap and the sidebar re-lays out. Comparing against one neighbour at a time (rather
-- than computing an absolute insertion index) is what keeps variable-height blocks — a collapsed
-- 40px header vs an expanded 7-row section — from overshooting past each other.
--
-- layoutSidebar publishes pane._blockLayout: the shown blocks in visual order as {id, y, h}, where y
-- is the offset DOWN from the content frame's top. Cursor Y is converted into that same space.
-- ----------------------------------------------------------------------------
local REORDER_EDGE   = 16   -- cursor within this many px of the pane edge auto-scrolls
local REORDER_SCROLL = 8    -- px per tick of auto-scroll
local REORDER_THROTTLE = 0.03

local dragState = {}
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()

local function stopReorder()
  if dragState.button then dragState.button:SetAlpha(1) end
  dragState.id, dragState.button = nil, nil
  dragDriver:Hide()
  saveSectionState()   -- persist the new order per character
end

-- Swap two ids in the active order array (by id, not by index — pane._blockLayout only holds the
-- SHOWN blocks, so its indices aren't guaranteed to line up with the order array's).
local function swapBlocks(idA, idB)
  local order = currentOrder()
  local ia, ib
  for i, id in ipairs(order) do
    if id == idA then ia = i elseif id == idB then ib = i end
  end
  if not (ia and ib) then return false end
  order[ia], order[ib] = order[ib], order[ia]
  return true
end

dragDriver:SetScript("OnUpdate", function(self, elapsed)
  self._t = (self._t or 0) + (elapsed or 0)
  if self._t < REORDER_THROTTLE then return end
  self._t = 0

  local pane = CP._sidebar
  local content = pane and pane._content
  local blocks = pane and pane._blockLayout
  -- The button can be released off-frame (or the panel closed mid-drag) without OnDragStop firing.
  if not (dragState.id and content and blocks) or not IsMouseButtonDown("LeftButton") then
    return stopReorder()
  end

  local _, cursorY = GetCursorPosition()
  cursorY = cursorY / (content:GetEffectiveScale() or 1)
  local top = content:GetTop()
  if not top then return end
  local offset = top - cursorY   -- px down from the content top == the same space as block.y

  -- Auto-scroll when dragging against either edge, so a block can reach an off-screen position.
  local scroll = pane._scroll
  if scroll and scroll.GetVerticalScrollRange then
    local sTop, sBottom = scroll:GetTop(), scroll:GetBottom()
    local cur = scroll:GetVerticalScroll() or 0
    if sTop and cursorY > sTop - REORDER_EDGE then
      scroll:SetVerticalScroll(max(0, cur - REORDER_SCROLL))
    elseif sBottom and cursorY < sBottom + REORDER_EDGE then
      scroll:SetVerticalScroll(min(scroll:GetVerticalScrollRange() or 0, cur + REORDER_SCROLL))
    end
  end

  local cur
  for i, b in ipairs(blocks) do if b.id == dragState.id then cur = i break end end
  if not cur then return end

  local swapWith
  local above, below = blocks[cur - 1], blocks[cur + 1]
  if above and offset < above.y + above.h / 2 then
    swapWith = above.id
  elseif below and offset > below.y + below.h / 2 then
    swapWith = below.id
  end

  if swapWith and swapBlocks(dragState.id, swapWith) then
    if PlaySound then pcall(PlaySound, "igMainMenuOptionCheckBoxOn") end
    if CP.LayoutSidebar then CP.LayoutSidebar() end
  end
end)

-- Make a header a shift-drag reorder handle. Shared by createCategoryHeader and createItemLevelRow.
local function enableHeaderReorder(button, blockId)
  button._blockId = blockId
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function(self)
    -- Plain (unmodified) drag stays inert, as it was before reorder existed — requiring the modifier
    -- means a user dragging across headers to read them can't scramble their layout by accident.
    if not IsShiftKeyDown() then return end
    dragState.id, dragState.button = blockId, self
    self:SetAlpha(0.55)
    dragDriver._t = 0
    dragDriver:Show()
  end)
  button:SetScript("OnDragStop", stopReorder)
end

-- ----------------------------------------------------------------------------
-- Tooltip rendering for a stat row (pcall the getter — §B).
-- ----------------------------------------------------------------------------
local function showRowTooltip(row)
  local data = row._data
  if not data or data.isHeader or not data.el then return end
  local ok, value, tipTitle, tipBody, tipLines = pcall(data.el.func)
  if not ok then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if type(tipLines) == "table" then
    if tipTitle then GameTooltip:SetText(tipTitle, 1, 1, 1) else GameTooltip:SetText(data.el.name, 1, 1, 1) end
    for _, line in ipairs(tipLines) do
      if line.right then
        GameTooltip:AddDoubleLine(line.left or "", line.right, 1, 0.82, 0, 1, 1, 1)
      else
        GameTooltip:AddLine(line.left or " ", 1, 0.82, 0, not line.white)
      end
    end
  else
    GameTooltip:SetText(tipTitle or data.el.name, 1, 1, 1)
    if tipBody and tipBody ~= "" then GameTooltip:AddLine(tipBody, 1, 0.82, 0, true) end
  end
  GameTooltip:Show()
end

-- ----------------------------------------------------------------------------
-- DOWNPORT/REPORT: faithful NewEra — header + stat rows built ONCE into a tall content frame, laid out
-- at cumulative Y, scrolled by PIXELS. createCategoryHeader = a 197x40 Button (title CENTER(0,1),
-- collapse-on-click); createStatRow = a 187x15 Button (faint neutral alternating bg, label/value).
-- ----------------------------------------------------------------------------

-- A category header: 197x40 Button. Clicking toggles the section's collapse state + re-lays out.
local function createCategoryHeader(content, section)
  local row = CreateFrame("Button", nil, content)
  row:SetSize(HEADER_W, HEADER_H)
  row._section = section

  -- Header art (197x40). DOWNPORT: the UI-Character-Info-Title atlas isn't shipped on 3.3.5a, so fall
  -- back to a solid tint (sized to 197x40).
  local headerBg = row:CreateTexture(nil, "ARTWORK", nil, 0)
  headerBg:SetAllPoints(row)
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(headerBg, "UI-Character-Info-Title", false)) then
    headerBg:SetTexture(0.16, 0.13, 0.10, 0.9)  -- DOWNPORT: tint fallback for the missing title atlas
  end
  row._headerBg = headerBg

  -- Collapse/expand toggle.
  local toggle = row:CreateTexture(nil, "OVERLAY")
  toggle:SetSize(14, 14)
  toggle:SetPoint("LEFT", row, "LEFT", 6, 0)
  toggle:SetVertexColor(1, 0.82, 0)
  row._toggle = toggle

  -- Title text, centered on the header (NewEra: CENTER(0,1)).
  local headerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  headerText:SetPoint("CENTER", headerBg, "CENTER", 0, 1)
  headerText:SetText(section.title)
  row._label = headerText

  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", function()
    -- Shift is the reorder modifier — a shift-click that never passed the drag threshold must not
    -- also collapse the section, or every abandoned drag silently toggles it.
    if IsShiftKeyDown() then return end
    sectionExpanded[section.id] = not sectionExpanded[section.id]
    saveSectionState()   -- persist per character so /reload keeps this section's open/closed state
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    if CP.LayoutSidebar then CP.LayoutSidebar() end
  end)
  enableHeaderReorder(row, section.id)
  return row
end

-- Registry of stat elements by id (el.func is looked up live on every hover,
-- so an external addon can override CP._statElements[id].func in place - e.g.
-- Enhanced Character Stats replacing "hit"/"s_hit"/"r_hit" with a talent-aware
-- breakdown - with no need to rebuild or re-anchor any row).
CP._statElements = CP._statElements or {}
function CP.GetStatElement(id)
  return CP._statElements[id]
end

-- A stat row: 187x15 Button. Faint neutral alternating bg (user preference — NOT the brown atlas).
local function createStatRow(content, el)
  local row = CreateFrame("Button", nil, content)
  row:SetSize(ROW_W, ROW_H)
  row._el = el
  if el.id then CP._statElements[el.id] = el end

  -- Alternating-row bg (faint neutral white tint). Shown on even rows by the layout pass.
  local rowBg = row:CreateTexture(nil, "BACKGROUND")
  rowBg:SetPoint("CENTER", row, "CENTER", 0, 0)
  rowBg:SetSize(ROW_W, ROW_H)
  rowBg:SetTexture(1, 1, 1)
  rowBg:SetVertexColor(1, 1, 1)
  rowBg:SetAlpha(0.05)
  rowBg:Hide()
  row._bounce = rowBg

  -- Hover highlight.
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.3)

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  label:SetPoint("LEFT", row, "LEFT", 11, 0)
  label:SetJustifyH("LEFT")
  label:SetText(el.name)
  row._label = label

  local value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  value:SetJustifyH("RIGHT")
  row._value = value

  -- Tooltip uses showRowTooltip, which reads row._data.el.
  row._data = { isHeader = false, el = el }
  row:SetScript("OnEnter", showRowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

-- The retail "Item Level" block: pinned above General. Structured exactly like a category section —
-- the SAME 197x40 header art carrying the centered "Item Level" title and the same +/- toggle, with
-- the quality-colored number sitting BELOW the box on the dark pane, the way stat rows sit under
-- their own headers. Collapsing hides the number and shrinks the block to the bare header, matching
-- how the stat categories behave. DOWNPORT: _G.ITEM_LEVEL is a format template ("Item Level %d"),
-- not a plain label — use a literal string here instead of formatting it in.
--
-- The container is a Frame with the header as a Button CHILD (not a Button itself), so only the
-- 197x40 art toggles — clicking the number strip below it does nothing, same as a stat row area.
local function createItemLevelRow(content)
  local row = CreateFrame("Frame", nil, content)
  row:SetSize(HEADER_W, ITEMLEVEL_ROW_H)

  -- Header box: top 197x40 of the block, identical art/'title' treatment to createCategoryHeader.
  local header = CreateFrame("Button", nil, row)
  header:SetSize(HEADER_W, HEADER_H)
  header:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row._header = header

  local bg = header:CreateTexture(nil, "ARTWORK", nil, 0)
  bg:SetAllPoints(header)
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(bg, "UI-Character-Info-Title", false)) then
    bg:SetTexture(0.16, 0.13, 0.10, 0.9)  -- DOWNPORT: tint fallback for the missing title atlas
  end

  -- Collapse/expand toggle — same art, placement and tint as createCategoryHeader's.
  local toggle = header:CreateTexture(nil, "OVERLAY")
  toggle:SetSize(14, 14)
  toggle:SetPoint("LEFT", header, "LEFT", 6, 0)
  toggle:SetVertexColor(1, 0.82, 0)
  row._toggle = toggle

  local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("CENTER", bg, "CENTER", 0, 1)
  label:SetText(L("ITEM_LEVEL_LABEL", "Item Level"))

  header:RegisterForClicks("LeftButtonUp")
  header:SetScript("OnClick", function()
    if IsShiftKeyDown() then return end   -- shift is the reorder modifier (see enableHeaderReorder)
    sectionExpanded[ITEMLEVEL_ID] = not sectionExpanded[ITEMLEVEL_ID]
    saveSectionState()   -- persist per character, exactly like a category header toggle
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    if CP.LayoutSidebar then CP.LayoutSidebar() end
  end)
  enableHeaderReorder(header, ITEMLEVEL_ID)

  -- The number, centered on the strip BELOW the box (not inside the art).
  local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  value:SetPoint("TOP", bg, "BOTTOM", 0, -3)
  row._value = value

  return row
end

-- Lay out the Item Level block at `y` and return its visual height (nil = not shown). Player mode
-- only — retail doesn't show item level for pets. Collapsed = header art only, so the block shrinks
-- to HEADER_H, the number hides, and the 17-slot ilvl scan is skipped entirely.
local function layoutItemLevelBlock(pane, content, y)
  local ilvlRow = pane._itemLevelRow
  if not ilvlRow then return nil end
  if CP._sidebarPetMode then ilvlRow:Hide(); return nil end

  local expanded = sectionExpanded[ITEMLEVEL_ID]
  ilvlRow._toggle:SetTexture(expanded
    and "Interface\\Buttons\\UI-MinusButton-Up"
    or  "Interface\\Buttons\\UI-PlusButton-Up")

  local valueFS = ilvlRow._value
  if expanded then
    local avg, quality = averageItemLevel()
    valueFS:SetText(tostring(floor(avg + 0.5)))
    local qc = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if qc then valueFS:SetTextColor(qc.r, qc.g, qc.b) else valueFS:SetTextColor(1, 1, 1) end
    valueFS:Show()
  else
    valueFS:Hide()
  end

  local blockH = expanded and ITEMLEVEL_ROW_H or HEADER_H
  ilvlRow:SetHeight(blockH)
  ilvlRow:ClearAllPoints()
  ilvlRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
  ilvlRow:Show()
  return blockH
end

-- Lay out one stat section at `y` and return its visual height (nil = no such block in this mode).
local function layoutSectionBlock(pane, content, sectionId, y)
  local sr = pane._sectionRows[sectionId]
  if not sr then return nil end

  -- Header at the fixed content right edge, at the running Y.
  local header = sr.header
  header:ClearAllPoints()
  header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
  header:Show()
  header._toggle:SetTexture(sectionExpanded[sectionId]
    and "Interface\\Buttons\\UI-MinusButton-Up"
    or  "Interface\\Buttons\\UI-PlusButton-Up")

  local blockH = HEADER_H
  if sectionExpanded[sectionId] then
    local anchorAbove, anchorIsHeader = header, true
    local statInCat = 0
    for _, row in ipairs(sr.rows) do
      statInCat = statInCat + 1
      row:ClearAllPoints()
      row:SetPoint("TOPRIGHT", anchorAbove, "BOTTOMRIGHT", anchorIsHeader and FIRST_ROW_INSET or 0, 0)
      -- Alternating bg by position within the section.
      if (statInCat % 2) == 0 then row._bounce:Show() else row._bounce:Hide() end
      row:Show()
      anchorAbove, anchorIsHeader = row, false
      blockH = blockH + ROW_H
    end
  else
    for _, row in ipairs(sr.rows) do row:Hide() end
  end
  return blockH
end

-- ----------------------------------------------------------------------------
-- Lay out all header+stat rows at cumulative Y honoring collapse state, set content height, resync bar.
-- Headers anchor to content.TOPRIGHT at the running Y (anti-cascade); first row after a header anchors
-- TOPRIGHT(-5,0) to the header's BOTTOMRIGHT; subsequent rows chain TOPRIGHT(0,0) row→row.
--
-- Block sequence comes from currentOrder() (shift+drag reorderable, saved per character), NOT from
-- the SECTIONS array — so Item Level is no longer hard-pinned to the top. Each block is followed by
-- HEADER_GAP of empty space, matching the pre-reorder spacing exactly.
-- ----------------------------------------------------------------------------
local function layoutSidebar()
  loadSectionState()   -- restore per-character collapse state + order once NE.db is ready (idempotent)
  local pane = CP._sidebar
  if not (pane and pane._content and pane._sectionRows) then return end
  local content = pane._content

  -- DOWNPORT/REPORT: first hide EVERY built section (player + pet), then lay out only the active
  -- set, so switching player<->pet mode never leaves the other set's rows visible.
  for _, sr in pairs(pane._sectionRows) do
    if sr.header then sr.header:Hide() end
    for _, row in ipairs(sr.rows) do row:Hide() end
  end

  local runningY = 0
  local blocks = {}          -- shown blocks in visual order — the reorder drag's hit-test map
  pane._blockLayout = blocks

  for _, id in ipairs(currentOrder()) do
    local blockH = (id == ITEMLEVEL_ID)
      and layoutItemLevelBlock(pane, content, runningY)
      or  layoutSectionBlock(pane, content, id, runningY)
    if blockH then
      blocks[#blocks + 1] = { id = id, y = runningY, h = blockH }
      runningY = runningY + blockH + HEADER_GAP
    end
  end

  content:SetHeight(runningY > 0 and runningY or 1)

  -- Clamp the scroll if the content shrank below the current offset. The custom bar resyncs via its
  -- OnScrollRangeChanged hook + throttled OnUpdate fallback (it polls the ScrollFrame range/value).
  local scroll = pane._scroll
  if scroll then
    local range = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
    local cur   = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
    if cur > range then scroll:SetVerticalScroll(range) end
  end
end
CP.LayoutSidebar = layoutSidebar

-- Recompute every stat row's value (pcall the getter — §B), then re-lay out (collapse may have changed).
local function refreshSidebar()
  local pane = CP._sidebar
  if not pane then return end
  if pane._sectionRows then
    for _, section in ipairs(activeSections()) do
      local sr = pane._sectionRows[section.id]
      if sr then
        for _, row in ipairs(sr.rows) do
          -- DOWNPORT/REPORT: pet rows may carry a relabel() (power token differs per pet) — re-apply.
          if row._el and row._el.relabel and row._label then
            local okN, nm = pcall(row._el.relabel)
            if okN and nm then row._label:SetText(nm) end
          end
          local ok, frameText = pcall(row._el.func)
          row._value:SetText((ok and frameText ~= nil) and tostring(frameText) or "--")
          -- Remember the movement-speed row so the ticker below can repaint just that one value
          -- instead of re-running all ~40 getters + a full relayout several times a second.
          if row._el and row._el.id == SPEED_ID then pane._speedRow = row end
        end
      end
    end
  end
  layoutSidebar()
end
CP.RefreshSidebar = refreshSidebar

-- ----------------------------------------------------------------------------
-- Live movement-speed ticker. GetUnitSpeed reports CURRENT speed and fires no event, so the one stat
-- in this panel that can't be event-driven has to be polled. Bounded hard: the driver only runs
-- while the stats pane is actually shown (buildSidebar hooks it to the pane's OnShow/OnHide), and it
-- repaints a single FontString rather than calling refreshSidebar.
-- ----------------------------------------------------------------------------
local SPEED_TICK = 0.2
local speedTicker = CreateFrame("Frame")
speedTicker:Hide()
speedTicker:SetScript("OnUpdate", function(self, elapsed)
  self._t = (self._t or 0) + (elapsed or 0)
  if self._t < SPEED_TICK then return end
  self._t = 0
  local pane = CP._sidebar
  -- IsVisible, not IsShown: the pane frame's own shown flag stays true while the whole character
  -- panel is closed, so IsShown would keep repainting a row nobody can see.
  local row = pane and pane._speedRow
  if not (row and row._value and row:IsVisible()) then return end
  local ok, text = pcall(movementSpeedText)
  row._value:SetText(ok and text or "--")
end)

-- ----------------------------------------------------------------------------
-- Build the sidebar: NE_CharacterStatsPane (in InsetRight) → ScrollFrame → tall content → all rows.
-- DOWNPORT/REPORT: pixel-scroll (plain ScrollFrame), faithful NewEra cumulative-Y layout.
-- ----------------------------------------------------------------------------
local function buildSidebar()
  if CP._sidebar then return CP._sidebar end
  local f = CP.frame
  local insetRight = f and (f.InsetRight or CP.InsetRight)
  if not insetRight then log("buildSidebar: InsetRight not ready"); return nil end

  -- Publish the contract-surface aliases (the brief names NE.charpanel.{Inset, InsetRight}); the
  -- foundation only set them as frame fields. Non-destructive.
  CP.InsetRight = CP.InsetRight or insetRight
  CP.Inset      = CP.Inset      or f.Inset

  -- Pane fills InsetRight's interior — DOWNPORT/REPORT: NewEra TOPLEFT(3,-3)/BOTTOMRIGHT(-3,2).
  local pane = CreateFrame("Frame", "NE_CharacterStatsPane", insetRight)
  pane:SetPoint("TOPLEFT",     insetRight, "TOPLEFT",     PANE_INSET, -PANE_INSET)
  pane:SetPoint("BOTTOMRIGHT", insetRight, "BOTTOMRIGHT", -PANE_INSET,  2)
  CP._sidebar = pane

  -- Gate the movement-speed poll on the pane's visibility (nothing to poll for while it's hidden).
  -- CreateFrame returns a SHOWN frame, so OnShow won't fire for the state it's already in — sync once.
  pane:SetScript("OnShow", function() speedTicker._t = 0; speedTicker:Show() end)
  pane:SetScript("OnHide", function() speedTicker:Hide() end)
  if pane:IsShown() then speedTicker:Show() end

  -- The pane exists now — let PaperDoll.lua attach the class-themed background.
  if CP.ApplyClassBackground then pcall(CP.ApplyClassBackground) end

  -- Plain ScrollFrame (pixel-scrolled). Leaves room for the custom bar on the right.
  local scroll = CreateFrame("ScrollFrame", "NE_StatsScrollFrame", pane)
  scroll:SetPoint("TOPLEFT",     pane, "TOPLEFT",       0, 0)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SCROLLBAR_GAP, 0)
  scroll:EnableMouseWheel(true)
  pane._scroll = scroll

  -- Content frame (the scroll child): fixed 197 wide, TALL (height set by layoutSidebar). Anchored
  -- TOPLEFT so SetVerticalScroll moves it; SetScrollChild ties it to the ScrollFrame.
  local content = CreateFrame("Frame", "NE_StatsContent", scroll)
  content:SetWidth(HEADER_W)
  content:SetHeight(1)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  scroll:SetScrollChild(content)
  pane._content = content

  -- The Item Level block (player mode only). Collapsible, and reorderable like any other block —
  -- layoutSidebar places it wherever currentOrder() says, defaulting to the top.
  pane._itemLevelRow = createItemLevelRow(content)

  -- Build all header + stat rows ONCE, grouped per section. DOWNPORT/REPORT: build BOTH the player
  -- sections AND the pet sections (unique ids) into the same content frame; layoutSidebar shows only
  -- the active set (player vs pet) so CP.ExpandPetSidebar can swap stat owners with no rebuild.
  pane._sectionRows = {}
  for _, set in ipairs({ SECTIONS, PET_SECTIONS }) do
    for _, section in ipairs(set) do
      local sr = { header = createCategoryHeader(content, section), rows = {} }
      for _, el in ipairs(section.stats) do
        sr.rows[#sr.rows + 1] = createStatRow(content, el)
      end
      pane._sectionRows[section.id] = sr
    end
  end

  -- DOWNPORT/REPORT: drive the ScrollFrame's pixel scroll with the existing custom scrollbar widget,
  -- adapted to SetVerticalScroll via NE.scrollbar.BuildCustomPixel.
  if NE.scrollbar and NE.scrollbar.BuildCustomPixel then
    -- DOWNPORT/REPORT(user): x=-1 → bar sits flush-right in the reserved gap (≈1px from the pane edge)
    -- instead of 4px left-of-the-scrollframe (which left a gap on the bar's right + clipped values).
    pcall(NE.scrollbar.BuildCustomPixel, scroll, { x = -1 })
  end

  refreshSidebar()   -- compute values + initial layout
  return pane
end
CP.BuildSidebar = buildSidebar

-- ----------------------------------------------------------------------------
-- SelectSidebar(i) — pick which pane shows in InsetRight (replaces the foundation stub).
--   1 = stats pane (our NE_CharacterStatsPane)
--   2 = titles (no system on 3.3.5; never selected — tab is disabled)
--   3 = equipment manager (Agent E's NE.charpanel.ShowEquipManager; guard if absent)
-- Always reflects the choice in the sidebar tab strip (SetSidebarTabSelected, from SidebarTabs.lua).
-- ----------------------------------------------------------------------------
local function selectSidebar(i)
  i = tonumber(i) or 1
  CP._activeSidebar = i

  local pane = CP._sidebar or buildSidebar()
  local equipPane = CP._equipPane

  if i == 3 then
    if pane then pane:Hide() end
    -- Equipment manager pane is Agent E's surface. Guard: if absent, fall back to stats.
    if CP.ShowEquipManager then
      local ok = pcall(CP.ShowEquipManager)
      if not ok then
        if pane then pane:Show(); refreshSidebar() end
        CP._activeSidebar = 1; i = 1
      end
    else
      log("SelectSidebar(3): ShowEquipManager absent; staying on stats")
      if pane then pane:Show(); refreshSidebar() end
      CP._activeSidebar = 1; i = 1
    end
  else
    -- Stats (1) — hide any equip pane and show the stats pane.
    if equipPane then equipPane:Hide() end
    if CP.HideEquipManager then pcall(CP.HideEquipManager) end
    if pane then pane:Show(); refreshSidebar() end
    if i ~= 1 then CP._activeSidebar = 1; i = 1 end
  end

  if CP.SetSidebarTabSelected then pcall(CP.SetSidebarTabSelected, i) end
end
CP.SelectSidebar = selectSidebar

-- ----------------------------------------------------------------------------
-- ReassertLayout — re-apply the resting sidebar layout (replaces the foundation stub). The foundation's
-- CharacterPanel.lua positions the slots/model; here we additionally restore the sidebar's expand state
-- + active pane so a re-show lands consistent. Out-of-combat only (touches our non-protected frame).
-- DOWNPORT: the original foundation ReassertLayout (slot/model positioning) is preserved by calling
-- through to it if it stashed the slot logic; we re-implement the sidebar half here.
-- ----------------------------------------------------------------------------
local foundationReassert = CP._foundationReassertLayout
local function reassertLayout()
  -- Run the foundation's slot/model re-position first (kept under a stashed ref).
  if foundationReassert then pcall(foundationReassert) end
  if InCombatLockdown() then return end
  -- Re-apply sidebar visuals if the sidebar is currently expanded.
  if CP.IsSidebarExpanded and CP.IsSidebarExpanded() then
    if not CP._sidebar then buildSidebar() end
    selectSidebar(CP._activeSidebar or 1)
  end
end

-- Stash the foundation ReassertLayout once, then take it over (load order: this file runs after
-- CharacterPanel.lua, so CP.ReassertLayout already points at the slot/model re-positioner).
if CP.ReassertLayout and CP.ReassertLayout ~= reassertLayout then
  CP._foundationReassertLayout = CP.ReassertLayout
  foundationReassert = CP._foundationReassertLayout
end
CP.ReassertLayout = reassertLayout

-- ----------------------------------------------------------------------------
-- Expand / Collapse convenience wrappers around the foundation's SetSidebarExpanded.
-- ExpandSidebar grows the frame 338->548, shows InsetRight + the tab strip, builds + shows the stats
-- pane (default selection 1). CollapseSidebar shrinks back to 338 and hides InsetRight.
-- ----------------------------------------------------------------------------
local function sidebarStrip()
  local f = CP.frame
  return (f and f._neSidebarTabs) or CP.SidebarTabs
end

-- DOWNPORT/REPORT: snap the stats sidebar back to the TOP when entering Character/Pet. The sidebar
-- uses a real pixel ScrollFrame (not the Faux scrolls reset in TabButtons), so it kept its offset
-- across tab switches. SetVerticalScroll(0) also re-syncs the custom thumb (BuildCustomPixel hooks
-- OnVerticalScroll). Deferred once so it runs after layoutSidebar has set the scroll range.
local function resetSidebarScrollTop()
  local pane = CP._sidebar
  local scroll = pane and pane._scroll
  if not (scroll and scroll.SetVerticalScroll) then return end
  pcall(scroll.SetVerticalScroll, scroll, 0)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() pcall(scroll.SetVerticalScroll, scroll, 0) end)
  end
end

local function expandSidebar()
  -- DOWNPORT/REPORT: player mode — the stats sidebar reads the PLAYER's stats.
  CP._sidebarPetMode = false
  if CP.SetSidebarExpanded then CP.SetSidebarExpanded(true) end
  -- The stats/titles/equipment tab strip is PLAYER-only — show it in player mode.
  local strip = sidebarStrip()
  if strip then strip:Show() end
  buildSidebar()
  selectSidebar(CP._activeSidebar or 1)
  resetSidebarScrollTop()
end
CP.ExpandSidebar = expandSidebar

-- DOWNPORT/REPORT: ExpandPetSidebar — the Pet tab is two-pane like Character (model in the Inset,
-- PET stats in the InsetRight sidebar). selectTab calls this on the Pet tab. It sets PET mode, expands
-- the sidebar (frame 548 + InsetRight shown), forces the stats pane (never the equipment manager), then
-- relays out the pet sections. Faithful to NewEra Sidebar.lua:751 / PetPaperDoll.CP.ExpandPetSidebar.
local function expandPetSidebar()
  CP._sidebarPetMode = true
  if CP.SetSidebarExpanded then CP.SetSidebarExpanded(true) end
  local pane = buildSidebar()
  -- Always the stats pane in pet mode (no titles/equipment sidebars for a pet) → hide the tab strip.
  local strip = sidebarStrip()
  if strip then strip:Hide() end
  if CP._equipPane then CP._equipPane:Hide() end
  if CP.HideEquipManager then pcall(CP.HideEquipManager) end
  CP._activeSidebar = 1
  if pane then pane:Show() end
  if CP.SetSidebarTabSelected then pcall(CP.SetSidebarTabSelected, 1) end
  refreshSidebar()
  resetSidebarScrollTop()
end
CP.ExpandPetSidebar = expandPetSidebar

local function collapseSidebar()
  if CP.SetSidebarExpanded then CP.SetSidebarExpanded(false) end
  if CP._sidebar then CP._sidebar:Hide() end
  if CP._equipPane then CP._equipPane:Hide() end
end
CP.CollapseSidebar = collapseSidebar

-- ToggleSidebar — flips expand state (used by SidebarTabs / any caller). Combat-safe (frame width
-- changes are legal on our non-protected frame).
local function toggleSidebar()
  if CP.IsSidebarExpanded and CP.IsSidebarExpanded() then
    collapseSidebar()
  else
    expandSidebar()
  end
end
CP.ToggleSidebar = toggleSidebar

-- ----------------------------------------------------------------------------
-- Live refresh: rebuild stat values when they change while the panel is open. The stat getters all
-- read live, so we just repaint the visible rows. Bounded to when the pane is shown.
-- ----------------------------------------------------------------------------
local refresher = CreateFrame("Frame")
local REFRESH_EVENTS = {
  "UNIT_STATS", "UNIT_AURA", "UNIT_DAMAGE", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER",
  "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_RESISTANCES", "UNIT_MAXHEALTH", "UNIT_MAXPOWER",
  "PLAYER_DAMAGE_DONE_MODS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
  "SPELL_POWER_CHANGED", "PLAYER_LEVEL_UP",
  "UPDATE_INVENTORY_DURABILITY",   -- the Durability row's only trigger (repairs + damage taken)
}
for _, ev in ipairs(REFRESH_EVENTS) do pcall(refresher.RegisterEvent, refresher, ev) end
refresher:SetScript("OnEvent", function(_, event, unit)
  -- UNIT_* events: only react to the player.
  if unit and unit ~= "player" then return end
  local pane = CP._sidebar
  if pane and pane:IsShown() then refreshSidebar() end
end)

-- Hook the stock primary-stat updater too (fires whenever the paperdoll recomputes).
if _G.PaperDollFrame_SetPrimaryStats then
  pcall(hooksecurefunc, "PaperDollFrame_SetPrimaryStats", function()
    local pane = CP._sidebar
    if pane and pane:IsShown() then refreshSidebar() end
  end)
end

-- ----------------------------------------------------------------------------
-- Boot: build the pane at login (gated on the module being enabled). InsetRight exists by then
-- (InsetFrames.lua builds at PLAYER_LOGIN). Build defensively; the pane stays hidden until expanded.
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  local ok, err = pcall(buildSidebar)
  if not ok then log("sidebar build failed: " .. tostring(err)) end
end)