-- DragonUI_NewEra/modules/professions/RecipeList.lua — left-panel recipe list for
-- NE_ProfessionsCraftingFrame.
--
-- DOWNPORT: adapted from NewEra_ReferenceFolder/NewEra/Professions/ProfessionsRecipeList.lua and
-- the recipe-list sections of Crafting.lua. Core changes for 3.3.5a:
--
--   * WowScrollBoxList / CreateScrollBoxListTreeListView (retail-only) replaced with
--     FauxScrollFrameTemplate + a fixed row-button pool. This is the native 3.3.5a scrolling
--     pattern used throughout the base UI (TradeSkillFrame, QuestLogFrame, etc.).
--   * NE_ATLAS global replaced by NE.tex.SetAtlas (registered in Assets.lua).
--   * MenuUtil.CreateContextMenu (retail) replaced by UIDropDownMenu_* (3.3.5a native),
--     feature-gated so a missing API doesn't hard-error.
--   * All "right-click → Favorite" behaviour is preserved via the UIDropDownMenu path.
--
-- Exposes:
--   C.buildRecipeList(f)   — called once from Window.lua on first Show
--   C.RefreshRecipes()     — rebuilds C.flatList + re-renders the visible rows
--   C.BuildFlatList()      — populates C.flatList from the current tradeskill/craft data
--   C.UpdateFilterReset()  — show/hide the filter-reset (x) button
--   C.ResetFilters()       — restore C.filters to defaults (used on manual reset and window close)


local NE = DragonUI_NewEra
local L = NE:GetLocale()
NE.profcraft = NE.profcraft or {}
local C = NE.profcraft

-- ============================================================================
-- State
-- ============================================================================
C.filters   = C.filters   or { showLearned = true, makeable = false, skillUp = false, search = "" }
C._collapsed = C._collapsed or {}   -- [catName] = true when collapsed client-side
C.flatList  = C.flatList  or {}     -- output of BuildFlatList()
C._selectedKey = nil                -- recipe NAME string of the currently highlighted row

-- ============================================================================
-- Constants (mirrored from Window.lua for local use)
-- ============================================================================
local RECIPELIST_TL = C.RECIPELIST_TL or { 5, -72 }
local RECIPELIST_BL = C.RECIPELIST_BL or { 0,  5  }
local RECIPELIST_W  = C.RECIPELIST_W  or 274

local MAX_ROWS      = 22     -- baseline pool size; runtime expands to fill the visible content area
local ROW_H_CAT     = 24     -- category header height
local ROW_H_RECIPE  = 20     -- recipe row height (retail ProfessionsRecipeListRecipeTemplate)

-- Skill-up icon atlases (difficulty → atlas name). "trivial"/"nodifficulty" → no icon.
local SKILLUP_ATLAS = {
  optimal = "professions-icon-skill-high",
  medium  = "professions-icon-skill-medium",
  easy    = "professions-icon-skill-low",
}

-- Recipe text colour helpers.
local function learnedRGB()
  local c = _G.PROFESSION_RECIPE_COLOR
  if c and c.GetRGB then return c:GetRGB() end
  return 0.96, 0.89, 0.58   -- retail parchment-gold
end
local function unlearnedRGB()
  local c = _G.DISABLED_FONT_COLOR
  if c and c.GetRGB then return c:GetRGB() end
  return 0.5, 0.5, 0.5
end

-- Skill-difficulty colours (cog option "Colour names by skill difficulty"): orange = optimal,
-- yellow = medium, green = easy, grey = trivial. Prefer the stock TradeSkillTypeColor table.
local DIFF_COLOR = {
  optimal      = { 1.00, 0.50, 0.25 },
  medium       = { 1.00, 1.00, 0.00 },
  easy         = { 0.25, 0.75, 0.25 },
  trivial      = { 0.50, 0.50, 0.50 },
  nodifficulty = { 0.96, 0.96, 0.96 },
}
local function difficultyRGB(diff)
  local t = _G.TradeSkillTypeColor and _G.TradeSkillTypeColor[diff]
  if t and t.r then return t.r, t.g, t.b end
  local f = DIFF_COLOR[diff] or DIFF_COLOR.trivial
  return f[1], f[2], f[3]
end

-- ============================================================================
-- SavedVariables helpers for Favorites.
-- NE.db.profFavorites[professionName][recipeName] = true
-- ============================================================================
local function profKey()
  if C.mode == "craft" then
    if GetCraftDisplaySkillLine then
      local ok, v = pcall(GetCraftDisplaySkillLine); if ok and v and v ~= "" and v ~= "UNKNOWN" then return v end
    end
    if GetCraftName then
      local ok, v = pcall(GetCraftName); if ok and v and v ~= "" and v ~= "UNKNOWN" then return v end
    end
  else
    if GetTradeSkillLine then
      local ok, v = pcall(GetTradeSkillLine); if ok and v and v ~= "" and v ~= "UNKNOWN" then return v end
    end
  end
  return "?"
end

local function favStore()
  NE.db = NE.db or {}
  NE.db.profFavorites = NE.db.profFavorites or {}
  local key = profKey()
  NE.db.profFavorites[key] = NE.db.profFavorites[key] or {}
  return NE.db.profFavorites[key]
end

local function isFav(name) return name ~= nil and favStore()[name] == true end
local function toggleFav(name)
  if not name then return end
  local s = favStore(); s[name] = (not s[name]) or nil
end

-- ============================================================================
-- Era legacy API: read the native tradeskill/craft list into a category tree.
-- ============================================================================
local function readEraRecipeTree()
  if not (GetNumTradeSkills and GetTradeSkillInfo) then return {} end
  -- Expand all native headers so every recipe enumerates (we manage collapse client-side).
  local i = 1
  while i <= GetNumTradeSkills() do
    local _, st, _, isExp = GetTradeSkillInfo(i)
    if st == "header" and not isExp and ExpandTradeSkillSubClass then
      ExpandTradeSkillSubClass(i)
    end
    i = i + 1
  end
  local cats, cur = {}, nil
  for idx = 1, GetNumTradeSkills() do
    local name, st, numAvailable, _, _, numSkillUps = GetTradeSkillInfo(idx)
    if name then
      if st == "header" or st == "subheader" then
        cur = { name = name, recipes = {} }
        cats[#cats + 1] = cur
      else
        if not cur then
          cur = { name = (GetTradeSkillLine and GetTradeSkillLine()) or "", recipes = {} }
          cats[#cats + 1] = cur
        end
        cur.recipes[#cur.recipes + 1] = {
          index        = idx,
          name         = name,
          difficulty   = st,
          learned      = true,
          numAvailable = numAvailable or 0,
          numSkillUps  = numSkillUps  or 0,
        }
      end
    end
  end
  return cats
end

-- Enchanting (and Beast Training) use the Craft API.
local function readEraCraftTree()
  if not (GetNumCrafts and GetCraftInfo) then return {} end
  local i = 1
  while i <= GetNumCrafts() do
    local _, _, ct, _, isExp = GetCraftInfo(i)
    if ct == "header" and not isExp and ExpandCraftSkillLine then
      ExpandCraftSkillLine(i)
    end
    i = i + 1
  end
  local cats, cur = {}, nil
  for idx = 1, GetNumCrafts() do
    local name, _, ct, numAvailable = GetCraftInfo(idx)
    if name then
      if ct == "header" then
        cur = { name = name, recipes = {} }
        cats[#cats + 1] = cur
      else
        if not cur then
          cur = { name = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or "", recipes = {} }
          cats[#cats + 1] = cur
        end
        cur.recipes[#cur.recipes + 1] = {
          index        = idx,
          name         = name,
          difficulty   = ct,
          learned      = true,
          numAvailable = numAvailable or 0,
          numSkillUps  = 0,
          isCraft      = true,
        }
      end
    end
  end
  return cats
end

-- ============================================================================
-- BuildFlatList — applies filters and C._collapsed, produces C.flatList.
-- Each entry: { kind="cat"|"recipe", ... }
-- ============================================================================
function C.BuildFlatList()
  local cats = (C.mode == "craft") and readEraCraftTree() or readEraRecipeTree()
  local flat  = {}
  local filt  = C.filters
  local srch  = (filt.search or ""):lower()

  -- Favorites category at the top (mirrors retail favoritesCategoryInfo).
  local favRecipes = {}
  for _, cat in ipairs(cats) do
    for _, r in ipairs(cat.recipes) do
      if isFav(r.name) then favRecipes[#favRecipes + 1] = r end
    end
  end
  if #favRecipes > 0 then
    flat[#flat + 1] = { kind = "cat", name = _G.BATTLE_PET_FAVORITE or "Favorites", key = "__fav" }
    if not C._collapsed["__fav"] then
      for _, r in ipairs(favRecipes) do flat[#flat + 1] = { kind = "recipe", r = r } end
    end
  end

  for _, cat in ipairs(cats) do
    local visible = {}
    for _, r in ipairs(cat.recipes) do
      -- Lua 5.1: no goto; use skip flag instead.
      local skip = false
      if r.learned      and not filt.showLearned                                                  then skip = true end
      if not skip and filt.skillUp and (r.difficulty == "trivial" or r.difficulty == "nodifficulty") then skip = true end
      if not skip and filt.makeable and (r.numAvailable or 0) <= 0                              then skip = true end
      if not skip and srch ~= "" and not r.name:lower():find(srch, 1, true)                     then skip = true end
      if not skip then visible[#visible + 1] = r end
    end
    if #visible > 0 then
      flat[#flat + 1] = { kind = "cat", name = cat.name, key = cat.name }
      if not C._collapsed[cat.name] then
        for _, r in ipairs(visible) do
          flat[#flat + 1] = { kind = "recipe", r = r }
        end
      end
    end
  end

  C.flatList = flat
end

-- ============================================================================
-- Row widget builders (lazy; one shared pool of Button frames reused per scroll offset).
-- Both category and recipe widgets are built lazily on the same button, identified by kind.
-- ============================================================================
local function ensureCategoryWidgets(b)
  if b._catBuilt then return end
  b._catBuilt = true

  b.CatLeft = b:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(b.CatLeft, "professions-recipe-header-left", true)
  b.CatLeft:SetPoint("LEFT", b, "LEFT", 0, 2)

  b.CatRight = b:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(b.CatRight, "professions-recipe-header-right", true)
  b.CatRight:SetPoint("RIGHT", b, "RIGHT", 0, 2)

  b.CatCenter = b:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(b.CatCenter, "professions-recipe-header-middle", false)
  b.CatCenter:SetPoint("TOPLEFT",     b.CatLeft,  "TOPRIGHT",    0, 0)
  b.CatCenter:SetPoint("BOTTOMRIGHT", b.CatRight, "BOTTOMLEFT",  0, 0)

  local fontObj = _G.GameFontNormal_NoShadow and "GameFontNormal_NoShadow" or "GameFontNormal"
  b.CatLabel = b:CreateFontString(nil, "OVERLAY", fontObj)
  b.CatLabel:SetPoint("LEFT", b, "LEFT", 10, 2)
  b.CatLabel:SetJustifyH("LEFT")

  b.CollapseIcon = b:CreateTexture(nil, "ARTWORK")
  b.CollapseIcon:SetPoint("RIGHT", b, "RIGHT", -10, 2)
  b.CollapseIcon:SetSize(14, 10)

  b._catWidgets = { b.CatLeft, b.CatRight, b.CatCenter, b.CatLabel, b.CollapseIcon }
end

local function ensureRecipeWidgets(b)
  if b._recipeBuilt then return end
  b._recipeBuilt = true

  -- Skill-up indicator (small chevron icon + optional count text).
  b.SkillUps = CreateFrame("Button", nil, b)
  b.SkillUps:SetSize(26, 15)
  b.SkillUps:EnableMouse(false)
  b.SkillUps:SetPoint("LEFT", b, "LEFT", -9, 0)
  b.SkillUps.Icon = b.SkillUps:CreateTexture(nil, "OVERLAY")
  b.SkillUps.Icon:SetPoint("RIGHT", b.SkillUps, "RIGHT", 0, -1)
  b.SkillUps.Text = b.SkillUps:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.SkillUps.Text:SetShadowOffset(0, 0)
  b.SkillUps.Text:SetPoint("RIGHT", b.SkillUps.Icon, "LEFT", 0, 1)
  b.SkillUps.Text:Hide()

  b.RLabel = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.RLabel:SetShadowOffset(0, 0); b.RLabel:SetJustifyH("LEFT")
  b.RLabel:SetPoint("LEFT", b.SkillUps, "RIGHT", 4, 0)
  b.RLabel:SetPoint("RIGHT", b, "RIGHT", -36, 0)   -- leave room for Count; truncates long names
  b.RLabel:SetNonSpaceWrap(false)   -- never wrap; clip instead

  b.Count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.Count:SetShadowOffset(0, 0)
  b.Count:SetPoint("RIGHT", b, "RIGHT", -4, 0)

  b.Sel = b:CreateTexture(nil, "OVERLAY", nil, 2)
  NE.tex.SetAtlas(b.Sel, "professions_recipe_active", true)
  b.Sel:SetPoint("CENTER", b, "CENTER", 0, -1); b.Sel:Hide()

  b.Hover = b:CreateTexture(nil, "HIGHLIGHT")
  NE.tex.SetAtlas(b.Hover, "professions_recipe_hover", true)
  b.Hover:SetPoint("CENTER", b, "CENTER", 0, -1); b.Hover:SetAlpha(0.5)

  b._recipeWidgets = { b.SkillUps, b.RLabel, b.Count, b.Hover }
end

local function hideWidgets(list, extra)
  if list then for _, w in ipairs(list) do w:Hide() end end
  if extra then for _, w in ipairs(extra) do if w then w:Hide() end end end
end

local function getVisibleRowCount(rl)
  if not (rl and rl.Content) then return MAX_ROWS end
  local h = rl.Content:GetHeight() or 0
  -- During profession switches/layout churn, content height can briefly read as 0.
  -- Treat that as "layout not ready" instead of forcing a 1-row viewport.
  if h < ROW_H_RECIPE then
    return rl._lastVisibleRows or MAX_ROWS
  end
  local n = math.floor(h / ROW_H_RECIPE)
  if n < 1 then n = 1 end
  rl._lastVisibleRows = n
  return n
end

local function ensureRowPool(rl, count)
  rl._rowPool = rl._rowPool or {}
  for i = #rl._rowPool + 1, count do
    local btn = CreateFrame("Button", nil, rl.Content)
    btn:SetHeight(ROW_H_RECIPE)
    btn:Hide()
    rl._rowPool[i] = btn
  end
end

-- ============================================================================
-- Row initializers (called every scroll update to populate a pooled button).
-- ============================================================================
local function initCategoryRow(btn, entry, rl)
  ensureCategoryWidgets(btn)
  hideWidgets(btn._recipeWidgets, { btn.Sel })
  for _, w in ipairs(btn._catWidgets) do w:Show() end
  btn:SetHeight(ROW_H_CAT)
  btn:RegisterForClicks("LeftButtonUp")
  btn.CatLabel:SetText(entry.name)

  local function syncIcon()
    NE.tex.SetAtlas(btn.CollapseIcon,
      C._collapsed[entry.key] and "professions-recipe-header-expand"
                               or "professions-recipe-header-collapse", false)
  end
  syncIcon()

  btn:SetScript("OnEnter", nil); btn:SetScript("OnLeave", nil)
  btn:SetScript("OnClick", function()
    C._collapsed[entry.key] = not C._collapsed[entry.key]
    syncIcon()
    C.RefreshRecipes()
    if PlaySound then PlaySound(841) end
  end)
end

local function initRecipeRow(btn, entry, rl)
  local r = entry.r
  ensureRecipeWidgets(btn)
  hideWidgets(btn._catWidgets)
  for _, w in ipairs(btn._recipeWidgets) do w:Show() end
  btn:SetHeight(ROW_H_RECIPE)
  btn._recipe = r

  btn.RLabel:SetText(r.name)
  local cr, cg, cb = (r.learned and learnedRGB or unlearnedRGB)()
  -- Cog option: colour learned recipes by skill difficulty instead of the flat parchment-gold.
  if C.opts and C.opts.colorByDifficulty and r.learned then
    cr, cg, cb = difficultyRGB(r.difficulty)
  end
  btn.RLabel:SetVertexColor(cr, cg, cb)

  -- Skill-up chevron.
  local atlas = SKILLUP_ATLAS[r.difficulty]
  if atlas then
    NE.tex.SetAtlas(btn.SkillUps.Icon, atlas, true)
    local n, showTxt = r.numSkillUps or 0, false
    showTxt = (n > 1) and (r.difficulty == "optimal")
    btn.SkillUps.Text:SetShown(showTxt or false)
    if showTxt then btn.SkillUps.Text:SetText(n) end
    btn.SkillUps:Show()
  else
    btn.SkillUps:Hide()
  end

  -- Crafts-available count (shown in brackets when > 0).
  if (r.numAvailable or 0) > 0 then
    btn.Count:SetText((" [%d]"):format(r.numAvailable)); btn.Count:Show()
  else btn.Count:Hide() end

  -- Selection highlight.
  btn.Sel:SetShown(C._selectedKey ~= nil and C._selectedKey == r.name)

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(self, btnName)
    if btnName == "RightButton" then
      -- Right-click: Favorite toggle via UIDropDownMenu.
      if not r.learned then return end
      if UIDropDownMenu_Initialize then
        -- Reuse a single dropdown frame; re-init per click for the current recipe.
        -- (CreateFrame with a fixed global name every click leaks the prior frame.)
        local dd = C._favDropdown
        if not dd then
          dd = CreateFrame("Frame", "NE_ProfCraftFavDropDown", UIParent, "UIDropDownMenuTemplate")
          C._favDropdown = dd
        end
        UIDropDownMenu_Initialize(dd, function()
          local info = UIDropDownMenu_CreateInfo()
          info.text     = isFav(r.name) and (BATTLE_PET_UNFAVORITE or "Remove Favorite")
                                        or  (BATTLE_PET_FAVORITE   or "Set Favorite")
          info.notCheckable = true
          info.func = function()
            toggleFav(r.name); C.RefreshRecipes()
          end
          UIDropDownMenu_AddButton(info)
        end, "MENU")
        ToggleDropDownMenu(1, nil, dd, "cursor", 0, 0)
      end
      return
    end
    -- Left-click: select recipe.
    if r.isCraft then
      if SelectCraft then pcall(SelectCraft, r.index) end
    else
      if SelectTradeSkill then pcall(SelectTradeSkill, r.index) end
    end
    C._selectedKey = r.name
    if C.OnRecipeSelected then C.OnRecipeSelected(r) end
    -- Update all visible row highlights in-place (avoid full re-render on selection).
    if rl and rl._rowPool then
      for _, row in ipairs(rl._rowPool) do
        if row.Sel and row._recipe then
          row.Sel:SetShown(row._recipe.name == r.name)
        end
      end
    end
    if PlaySound then PlaySound(841) end
  end)

  btn:SetScript("OnEnter", function()
    -- Cog option: suppress the item tooltip while scrolling/hovering the list.
    if C.opts and C.opts.hideListTooltips then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local shown = false
    if r.isCraft and GameTooltip.SetCraftSpell then
      local ok = pcall(GameTooltip.SetCraftSpell, GameTooltip, r.index)
      shown = ok
    elseif GameTooltip.SetTradeSkillItem then
      local ok = pcall(GameTooltip.SetTradeSkillItem, GameTooltip, r.index)
      shown = ok
    end
    if not shown then
      GameTooltip:ClearLines()
      GameTooltip:AddLine(r.name or "Recipe", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip_Hide then GameTooltip_Hide() else GameTooltip:Hide() end
  end)
end

-- ============================================================================
-- FauxScrollFrame scroll callback: update the row pool from C.flatList + offset.
-- ============================================================================
local function refreshRows(rl)
  local list   = C.flatList
  local total  = #list
  local scroll = rl.ScrollFrame
  local offset = scroll and FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(scroll) or 0
  local visibleRows = getVisibleRowCount(rl)
  local canScroll = total > visibleRows

  ensureRowPool(rl, visibleRows)

  -- Update scrollbar.
  if FauxScrollFrame_Update and scroll then
    FauxScrollFrame_Update(scroll, total, visibleRows, ROW_H_RECIPE)
  end

  -- Defensive clamp: when content fits, force the hidden Faux slider to a zero range/value.
  -- This prevents stale drag state from producing phantom offsets on some client/UI stacks.
  if scroll and not canScroll then
    local sb = _G[(scroll:GetName() or "") .. "ScrollBar"]
    if sb then
      if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
      if sb.SetValue then sb:SetValue(0) end
    end
    offset = 0
  end

  -- Keep custom-bar visuals authoritative from recipe-list state (not transient slider state).
  -- This avoids a stale visible thumb after switching from a long profession list to a short one.
  local cbar = scroll and scroll._neCustomBar
  if cbar and cbar._alwaysShow then
    cbar:Show()
    if cbar._upBtn then cbar._upBtn:Show() end
    if cbar._downBtn then cbar._downBtn:Show() end
    if cbar._thumb then
      if canScroll then cbar._thumb:Show() else cbar._thumb:Hide() end
    end
  end

  for i = 1, visibleRows do
    local btn   = rl._rowPool[i]
    local idx   = offset + i
    local entry = list[idx]
    if entry then
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT",  rl.Content, "TOPLEFT",  14, -(i - 1) * ROW_H_RECIPE)
      btn:SetPoint("TOPRIGHT", rl.Content, "TOPRIGHT", -4, -(i - 1) * ROW_H_RECIPE)
      if entry.kind == "cat" then
        initCategoryRow(btn, entry, rl)
      else
        initRecipeRow(btn, entry, rl)
      end
      btn:Show()
    else
      btn:Hide()
    end
  end

  for i = visibleRows + 1, #rl._rowPool do
    if rl._rowPool[i] then rl._rowPool[i]:Hide() end
  end

  if rl.BottomFade then
    local hasMoreBelow = (offset + visibleRows) < total
    rl.BottomFade:SetShown(hasMoreBelow)
  end
end

-- ============================================================================
-- C.RefreshRecipes — rebuild flat list and re-render.
-- ============================================================================
function C.RefreshRecipes()
  C.BuildFlatList()
  local f  = C.frame
  local rl = f and f.RecipeList
  if not rl then return end
  refreshRows(rl)
  C.UpdateFilterReset()
end

-- ============================================================================
-- C.ResetFilters — restore C.filters to defaults. C.filters is shared across every
-- profession (module-level table, not per-profession), so this also runs on window
-- close to prevent filters picked for one profession leaking into the next.
-- ============================================================================
function C.ResetFilters()
  C.filters.showLearned   = true
  C.filters.makeable      = false
  C.filters.skillUp       = false
  C.filters.search        = ""
  local f  = C.frame
  local rl = f and f.RecipeList
  if rl and rl.SearchBox then rl.SearchBox:SetText("") end
  pcall(function() if SetTradeSkillSubClassFilter then SetTradeSkillSubClassFilter(0, 1, 1) end end)
  pcall(function() if SetTradeSkillInvSlotFilter  then SetTradeSkillInvSlotFilter(0,  1, 1) end end)
end

-- ============================================================================
-- C.UpdateFilterReset — show/hide the filter-reset (x) button.
-- ============================================================================
function C.UpdateFilterReset()
  local f  = C.frame
  local rl = f and f.RecipeList
  if not (rl and rl.FilterReset) then return end
  local filt  = C.filters
  local hasSearch = (filt.search and filt.search ~= "")
  local hasFilterToggles = (not filt.showLearned) or filt.makeable or filt.skillUp

  -- Avoid showing two clear buttons at once: while search text exists, use only the
  -- search-box clear button. Show the red reset button only for non-search filters.
  if hasFilterToggles and not hasSearch then rl.FilterReset:Show() else rl.FilterReset:Hide() end
end

-- ============================================================================
-- C.buildRecipeList(f) — creates the left-panel sub-frame. Called once on first Show.
-- ============================================================================
function C.buildRecipeList(f)
  local rl = CreateFrame("Frame", "NE_ProfessionsCraftingRecipeList", f)
  rl:SetWidth(RECIPELIST_W)
  rl:SetPoint("TOPLEFT",    f, "TOPLEFT",    RECIPELIST_TL[1], RECIPELIST_TL[2])
  rl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RECIPELIST_BL[1], RECIPELIST_BL[2])
  f.RecipeList = rl

  -- Background: Professions-background-summarylist atlas.
  local bg = rl:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(bg, "professions-background-summarylist", false)
  bg:SetAllPoints(rl)
  rl.Background = bg

  -- InsetFrame nineslice border.
  local ns = CreateFrame("Frame", nil, rl)
  ns:SetAllPoints(rl); ns:EnableMouse(false)
  if NE.nineslice and NE.nineslice.ApplyLayout then
    -- DOWNPORT: ApplyLayout is a plain function (container, layoutName) — no self arg.
    pcall(NE.nineslice.ApplyLayout, ns, "InsetFrameTemplate")
  end
  rl.BackgroundNineSlice = ns

  -- Filter button — positioned at TOPRIGHT of the list panel first, so the search box
  -- can anchor its RIGHT edge to the filter's LEFT (mirroring the reference layout).
  local filter = CreateFrame("Button", "NE_ProfessionsCraftingFilterBtn", rl, "UIPanelButtonTemplate")
  filter:SetSize(60, 18)
  filter:SetText(_G.FILTER or "Filter")
  -- Right edge sits 26px in from the panel (not the usual 8px) to reserve room for the
  -- filter-reset (x) button below, so it lands flush with the panel inset instead of
  -- overhanging past it.
  filter:SetPoint("TOPRIGHT", rl, "TOPRIGHT", -26, -9)
  rl.FilterDropdown = filter

  -- Search box: left-anchored to panel left, right edge bounded by the filter button.
  local search = CreateFrame("EditBox", "NE_ProfessionsCraftingSearch", rl)
  search:SetAutoFocus(false)
  search:SetHeight(20)
  search:SetPoint("TOPLEFT", rl, "TOPLEFT", 8, -8)
  search:SetPoint("RIGHT",  filter, "LEFT",  -4, 0)   -- right edge hugs filter's left
  search:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
  search:SetTextInsets(20, 18, 0, 0)
  if search.SetBackdrop then
    search:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    search:SetBackdropColor(0, 0, 0, 0.6)
    search:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end
  search:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
  search:SetScript("OnEnterPressed",  function(self) if self.ClearFocus then self:ClearFocus() end end)

  local icon = search:CreateTexture(nil, "OVERLAY")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", search, "LEFT", 4, 0)
  icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  search.SearchIcon = icon

  -- Local clear button (explicitly owned by us, no template-side effects).
  local searchClear = _G[search:GetName() .. "ClearButton"]
                   or search.ClearButton
                   or _G[search:GetName() .. "ResetButton"]
                   or search.ResetButton
  if not searchClear then
    searchClear = CreateFrame("Button", nil, search)
    searchClear:SetSize(16, 16)
    searchClear:SetPoint("RIGHT", search, "RIGHT", -2, 0)
    local ctex = searchClear:CreateTexture(nil, "OVERLAY")
    ctex:SetAllPoints(searchClear)
    if not NE.tex.SetAtlas(ctex, "common-search-clearbutton", false) then
      ctex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    end
    searchClear._tex = ctex
    searchClear:Hide()
  end

  local function clearSearch()
    if search then
      search:SetText("")
      if search.ClearFocus then search:ClearFocus() end
    end
  end
  searchClear:SetScript("OnClick", clearSearch)

  search:HookScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    -- SearchBoxTemplate can surface placeholder/instruction text as real GetText() on some
    -- clients/addon stacks. Treat that as empty so first open never starts pre-filtered.
    local ph = _G.SEARCH or "Search"
    if txt == ph and self.HasFocus and not self:HasFocus() then txt = "" end
    C.filters.search = txt
    if searchClear then
      if txt ~= "" then searchClear:Show() else searchClear:Hide() end
    end
    C.RefreshRecipes()
    C.UpdateFilterReset()
  end)
  -- Ensure first render starts unfiltered.
  C.filters.search = ""
  search:SetText("")
  rl.SearchBox = search

  filter:SetScript("OnClick", function(self)
    if not UIDropDownMenu_Initialize then return end

    -- Reuse a single dropdown frame (see fav dropdown note above).
    local dd = C._filterDropdown
    if not dd then
      dd = CreateFrame("Frame", "NE_ProfCraftFilterDropDown", UIParent, "UIDropDownMenuTemplate")
      C._filterDropdown = dd
    end

    -- Toggle: a second click on the filter button closes the open list instead of reopening it.
    if _G.UIDROPDOWNMENU_OPEN_MENU == dd and _G.DropDownList1 and _G.DropDownList1:IsShown() then
      if CloseDropDownMenus then CloseDropDownMenus() end
      return
    end

    UIDropDownMenu_Initialize(dd, function()
      local function toggle(key)
        C.filters[key] = not C.filters[key]; C.RefreshRecipes(); C.UpdateFilterReset()
      end

      local function addCheck(label, key)
        local info = UIDropDownMenu_CreateInfo()
        info.text = label; info.checked = C.filters[key]; info.keepShownOnClick = true
        info.func = function() toggle(key) end
        UIDropDownMenu_AddButton(info)
      end

      local showLearnedText   = (L and L["Show Learned"])   or "Show Learned"
      local hasSkillUpText    = (L and L["Has Skill Up"])   or "Has Skill Up"
      local haveMaterialsText = (L and L["Have Materials"]) or "Have Materials"

      addCheck(showLearnedText,   "showLearned")
      addCheck(hasSkillUpText,    "skillUp")
      addCheck(haveMaterialsText, "makeable")
    end, "MENU")

    -- Anchor the list to the filter button (drops below it) instead of at the cursor.
    ToggleDropDownMenu(1, nil, dd, self, 0, 0)
  end)
  rl.FilterDropdown = filter

  -- Filter-reset (x) button — shown when any filter is active.
  local reset = CreateFrame("Button", nil, rl)
  reset:SetSize(16, 16)
  reset:SetPoint("LEFT", filter, "RIGHT", 2, 0)
  local rtex = reset:CreateTexture(nil, "OVERLAY")
  rtex:SetAllPoints(reset)
  if not NE.tex.SetAtlas(rtex, "common-search-clearbutton", false) then
    rtex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  end
  reset:Hide()
  reset:SetScript("OnClick", function()
    -- Close the (possibly open) filter dropdown so its checkboxes can't go out of sync with the reset.
    if CloseDropDownMenus then CloseDropDownMenus() end
    C.ResetFilters()
    C.RefreshRecipes(); C.UpdateFilterReset()
  end)
  rl.FilterReset = reset

  -- Content frame (rows are anchored to this, sits below the search/filter bar).
  local content = CreateFrame("Frame", nil, rl)
  content:SetPoint("TOPLEFT",     search, "BOTTOMLEFT",  0, -4)
  content:SetPoint("BOTTOMRIGHT", rl,     "BOTTOMRIGHT", -22, 8)
  rl.Content = content

  -- Visual cue that the list continues below the fold.
  local bottomFade = content:CreateTexture(nil, "OVERLAY")
  bottomFade:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 0)
  bottomFade:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 0)
  bottomFade:SetHeight(56)
  if bottomFade.SetGradientAlpha then
    bottomFade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.9)
  else
    bottomFade:SetTexture(0, 0, 0, 0.75)
  end
  bottomFade:Hide()
  rl.BottomFade = bottomFade

  -- FauxScrollFrame (native 3.3.5a scrollable list).
  local scroll = CreateFrame("ScrollFrame", "NE_ProfessionsCraftingScroll", content, "FauxScrollFrameTemplate")
  scroll:SetAllPoints(content)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    local total = #(C.flatList or {})
    local visibleRows = getVisibleRowCount(rl)
    if total <= visibleRows then
      local sb = _G[(self:GetName() or "") .. "ScrollBar"]
      if sb then
        if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
        if sb.SetValue then sb:SetValue(0) end
      end
      refreshRows(rl)
      return
    end
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H_RECIPE, function() refreshRows(rl) end)
  end)
  -- DOWNPORT/REPORT: wheel scrolling via the (hidden) Faux slider value; auto-clamps to its range.
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = _G[(self:GetName() or "") .. "ScrollBar"]
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_H_RECIPE
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  rl.ScrollFrame = scroll

  -- Scrollbar: use the same hand-built minimal DF bar as the Character window's FauxScroll panes
  -- (Skills/Reputation/Honor/Currency). BuildCustom is a plain function (scrollFrame, opts) — the
  -- stock-slider Reskin path never rendered on 3.3.5a. x pushes the bar into the right gutter.
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    -- Keep the empty track visible when content fits (Auction House style), with thumb hidden.
    pcall(NE.scrollbar.BuildCustom, scroll, { x = -8, alwaysShow = true })
  end

  -- Row button pool (MAX_ROWS buttons, reused per scroll position).
  rl._rowPool = {}
  ensureRowPool(rl, MAX_ROWS)

  -- Initial population.
  C.RefreshRecipes()
end
