-- DragonUI_NewEra/modules/levelup/Register.lua — event wiring, enable toggle, options, test command.
--
-- Registration runs at PLAYER_LOGIN rather than at file load, for the reason
-- modules/cooldownviewer/Register.lua:39 records: DragonUI's AceDB profile — which the mover's
-- position round-trip reads and writes — is not guaranteed ready while our files are parsing.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup

-- ── Enable state ────────────────────────────────────────────────────────────────────────────────
--
-- Defaults ON: a level-up banner is the kind of thing a player expects to see happen, not to have
-- to go and find. The test command deliberately ignores this — running it is an explicit request.
function M.IsEnabled()
  if NE.db and NE.db.levelup and NE.db.levelup.enabled ~= nil then
    return NE.db.levelup.enabled and true or false
  end
  return true
end

function M.SetEnabled(v)
  if not NE.db then return end
  NE.db.levelup = NE.db.levelup or {}
  NE.db.levelup.enabled = v and true or false
end

-- The level-up fanfare. OFF by default: the client plays its own on a real level-up (confirmed in
-- game, 2026-08-01), so ours only ever doubled it. Kept as a setting rather than deleted because it
-- is the only way to hear anything from /nelevelup, which fires no engine sound.
function M.IsSoundEnabled()
  if NE.db and NE.db.levelup and NE.db.levelup.sound ~= nil then
    return NE.db.levelup.sound and true or false
  end
  return false
end

function M.SetSoundEnabled(v)
  if not NE.db then return end
  NE.db.levelup = NE.db.levelup or {}
  NE.db.levelup.sound = v and true or false
end

-- ── Live events ─────────────────────────────────────────────────────────────────────────────────
--
-- PLAYER_LEVEL_UP carries the NEW level as its first argument. Read it rather than calling
-- UnitLevel: at the moment the event fires UnitLevel can still report the old value, and a banner
-- reading "Level 39" on hitting 40 is the classic symptom.
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:SetScript("OnEvent", function(_, _, level)
  if not M.IsEnabled() then return end
  if not level then return end
  -- One frame's delay: the harvest's own PLAYER_LEVEL_UP handler refreshes battlegrounds, dungeons
  -- and talent totals off the same event, and handler order between two frames is not defined. The
  -- banner reads what they wrote, so it goes second.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() M.Show(level) end)
  else
    M.Show(level)
  end
end)

-- ── Test command ────────────────────────────────────────────────────────────────────────────────
--
-- Levelling to check a display change is not a workable loop, and neither prior port left a usable
-- one: the standalone addon's /lvltest hardcodes a 1-80 range, and NewEra's header advertises a
-- `/ne levelup` command that does not exist anywhere in that addon.
SLASH_NELEVELUP1 = "/nelevelup"
SlashCmdList["NELEVELUP"] = function(msg)
  msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.*)$")

  if cmd == "side" then
    M.ShowSide(tonumber(arg) or UnitLevel("player") or 1)
    return
  end

  if cmd == "coverage" then
    local c = M.Coverage()
    local _, classFile = UnitClass("player")
    print("|cff1784d1LevelUp|r " .. (GetRealmName() or "?") .. " / " .. (classFile or "?")
      .. ": " .. c.entries .. " abilities across " .. c.levels .. " levels, "
      .. c.bgs .. " battlegrounds, " .. c.dungeons .. " dungeons/raids.")
    if c.entries == 0 then
      print("|cff1784d1LevelUp|r no trainer data yet — visit any class trainer once to harvest it.")
    end
    return
  end

  if cmd == "harvest" then
    -- Manual re-run, for when the player is standing at a trainer and wants to confirm it worked.
    local n = M.harvest.HarvestTrainer()
    local b = M.harvest.HarvestBattlegrounds()
    local d = M.harvest.HarvestDungeons()
    print("|cff1784d1LevelUp|r harvested: " .. n .. " services, " .. b .. " battlegrounds, "
      .. d .. " dungeons/raids." .. ((n == 0) and " (Open a trainer window for services.)" or ""))
    return
  end

  local level = tonumber(cmd)
  if level and level >= 1 then
    M.Show(level)
    return
  end

  print("|cff1784d1LevelUp|r usage:")
  print("  /nelevelup <level>      preview the banner for a level")
  print("  /nelevelup side <level> preview the full grid panel")
  print("  /nelevelup harvest      re-read the open trainer / battleground / dungeon data")
  print("  /nelevelup coverage     what this realm and class has learned so far")
end

-- ── DragonUI wiring ─────────────────────────────────────────────────────────────────────────────

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()

  -- Build up front so the mover has a real frame to size itself against, and so the first level-up
  -- of a session is not also the first time this code runs.
  local banner = M.Build()
  M.BuildSide()

  -- Movable via DragonUI's edit mode. showTest/hideTest give the editor something to position
  -- against, since the banner is invisible the other 99% of the time.
  if NE.RegisterHUDFrame then
    NE.RegisterHUDFrame({
      name         = "NE_LevelUpDisplay",
      label        = "Level Up Display",
      frame        = banner,
      key          = "levelup",
      defaultPoint = M.DEFAULT_POINT,
      showTest     = function() M.Show(UnitLevel("player") or 10) end,
      hideTest     = function() M.Hide() end,
    })
  end

  if NE.RegisterOptionSection then
    NE.RegisterOptionSection({
      id    = "levelup",
      order = 45,
      build = function(scroll, C)
        if C.AddSpacer then C:AddSpacer(scroll) end
        C:AddHeading(scroll, "Level Up Display")
        C:AddDescription(scroll,
          "Retail's level-up banner. What it announces is read from |cffffcc55this server|r — "
          .. "abilities and their levels come from your class trainer's own list, battlegrounds "
          .. "and dungeons from the client's brackets. Visit a trainer once to fill it in; "
          .. "|cffffcc55/nelevelup coverage|r shows what it knows.")
        C:AddToggle(scroll, {
          label   = "Enable Level Up Display",
          desc    = "On by default. Turn off to stop the banner appearing on level-up; the harvest "
                    .. "keeps running either way, so turning it back on costs nothing.",
          getFunc = function() return M.IsEnabled() end,
          setFunc = function(v)
            M.SetEnabled(v)
            if not v then M.Hide(); M.HideSide() end
          end,
        })

        C:AddToggle(scroll, {
          label   = "Play the level-up sound",
          desc    = "|cffffcc55Off by default.|r The game already plays its own fanfare when you "
                    .. "level, so this only adds a second copy on top of it. Turn it on if you "
                    .. "want /nelevelup previews to make a sound, since those fire no game sound "
                    .. "of their own.",
          getFunc = function() return M.IsSoundEnabled() end,
          setFunc = function(v) M.SetSoundEnabled(v) end,
        })
      end,
    })
  end

  if NE.qa then
    NE.qa.modules = NE.qa.modules or {}
    table.insert(NE.qa.modules, {
      name  = "Level Up Display",
      frame = banner,
      open  = function() M.Show(UnitLevel("player") or 10) end,
      close = function() M.Hide(); M.HideSide() end,
    })
  end
end)
