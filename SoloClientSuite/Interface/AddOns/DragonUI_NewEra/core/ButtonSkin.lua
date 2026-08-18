-- DragonUI_NewEra/core/ButtonSkin.lua — shared modern button skin (NE.buttonskin.Skin).
--
-- DOWNPORT: NewEra Core/ButtonSkin.lua → 3.3.5a. Reskins a Button to retail's
-- BigRedThreeSliceButton (the red 3-slice ESC-menu/dialog button). NewEra called the NATIVE
-- Texture:SetAtlas (a retail/Era method) and read atlas dimensions via C_Texture.GetAtlasInfo.
-- On 3.3.5a there is no Texture:SetAtlas, so every piece-atlas swap routes through NE.tex.SetAtlas
-- (our coord registry), and dimensions come from NE.tex._atlasEntry. C_Texture.GetAtlasInfo is
-- the compat shim — present, but only answers for atlases the Asset agent registered, so the
-- whole reskin is FAIL-SAFE: missing 128-RedButton art → native button art kept (returns false).
--
-- §2 CONTRACT: exposed as NE.buttonskin.* (and NE.button.* kept for NewEra-name parity).
-- Taint-safe: adds BACKGROUND textures + hooks visual-state scripts only.

local NE = DragonUI_NewEra
NE.buttonskin = NE.buttonskin or {}
NE.button = NE.buttonskin            -- DOWNPORT: NewEra used NE.button; alias to the contract name

local ATLAS = "128-RedButton"

local function pieceNames(postfix)
  return ATLAS .. "-Left" .. postfix, "_" .. ATLAS .. "-Center" .. postfix, ATLAS .. "-Right" .. postfix
end

-- Port of ThreeSliceButtonMixin:UpdateScale.
--
-- DOWNPORT: retail's mixin does `self.Left:SetScale(scale)`. **Texture has no SetScale on 3.3.5a** —
-- ClassicAPI has to synthesise even GetEffectiveScale for a Region by delegating to its parent
-- (Util/WidgetAPI.lua:205), and adds no SetScale at all. So the caps are SIZED here instead, in real
-- pixels, and the trim branch below no longer divides back out by a scale that was never applied.
--
-- This never ran until the 128-RedButton sheet was shipped: Skin returns false before reaching here
-- when the atlas is missing, and every call site wraps it in pcall — so the error would have been
-- swallowed, leaving a button with three blank textures over its hidden native art.
local function updateScale(btn)
  local d = btn._neThreeSlice
  if not d or not d.leftInfo or not d.rightInfo then return end
  local buttonH, buttonW = btn:GetHeight(), btn:GetWidth()
  if buttonH <= 0 or d.leftInfo.height <= 0 then return end
  local scale = buttonH / d.leftInfo.height
  d.Left:SetHeight(buttonH); d.Right:SetHeight(buttonH)

  local leftW, rightW = d.leftInfo.width * scale, d.rightInfo.width * scale
  local both = leftW + rightW
  if both > buttonW then
    local extra = both - buttonW
    local newLeftW, newRightW = leftW, rightW
    if (leftW - extra) > rightW then
      newLeftW = leftW - extra
    elseif (rightW - extra) > leftW then
      newRightW = rightW - extra
    else
      if leftW ~= rightW then
        local uneven = math.abs(leftW - rightW)
        extra = extra - uneven
        newLeftW = math.min(leftW, rightW); newRightW = newLeftW
      end
      local half = extra / 2
      newLeftW = newLeftW - half; newRightW = newRightW - half
    end
    -- DOWNPORT: the texcoord trim composes the atlas sub-rect AFTER NE.tex.SetAtlas has set it.
    -- We re-resolve the atlas entry to compose the trim within the element's own rect.
    local le = NE.tex._atlasEntry(pieceNames(d.postfix or ""))
    d.Left:SetWidth(newLeftW)
    d.Right:SetWidth(newRightW)
    if le then
      d.Left:SetTexCoord(le.left, le.left + (le.right - le.left) * (newLeftW / leftW), le.top, le.bottom)
    end
  else
    NE.tex.SetAtlas(d.Left, pieceNames(d.postfix or ""), false)
    d.Left:SetWidth(leftW)
    d.Right:SetWidth(rightW)
  end
end

-- Faithful port of ThreeSliceButtonMixin:UpdateButton — swap the 3 atlases per state.
local function updateButton(btn, state)
  local d = btn._neThreeSlice
  if not d then return end
  state = state or (btn.GetButtonState and btn:GetButtonState()) or "NORMAL"
  if btn.IsEnabled and not btn:IsEnabled() then state = "DISABLED" end
  local postfix = (state == "DISABLED" and "-Disabled") or (state == "PUSHED" and "-Pressed") or ""
  d.postfix = postfix
  local l, c, r = pieceNames(postfix)
  -- DOWNPORT: native SetAtlas → NE.tex.SetAtlas.
  NE.tex.SetAtlas(d.Left,   l, true)
  NE.tex.SetAtlas(d.Center, c)
  NE.tex.SetAtlas(d.Right,  r, true)
  updateScale(btn)
end

-- Hide the button's native art so the 3-slice shows through.
local function hideNativeArt(btn)
  local name = btn.GetName and btn:GetName()
  for _, key in ipairs({ "Left", "Middle", "Right" }) do
    local t = btn[key] or (name and _G[name .. key])
    if t and t.SetTexture then t:SetTexture(nil); if t.Hide then t:Hide() end end
  end
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
    local t = btn[getter] and btn[getter](btn)
    if t and t.SetTexture then t:SetTexture(nil); if t.Hide then t:Hide() end end
  end
  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h and h.SetTexture then h:SetTexture(nil) end
end

-- Reskin `btn`. Idempotent. opts.atlas overrides the family. Returns true on success.
function NE.buttonskin.Skin(btn, opts)
  if not btn or btn._neThreeSlice then return btn and btn._neThreeSlice ~= nil end
  -- DOWNPORT: prefer our registry (NE.tex._atlasEntry) for dimensions; fall back to the
  -- C_Texture shim. If neither knows the atlas, fail-safe (native art kept).
  local leftInfo  = NE.tex._atlasEntry(ATLAS .. "-Left")
  local rightInfo = NE.tex._atlasEntry(ATLAS .. "-Right")
  if not (leftInfo and rightInfo) and C_Texture and C_Texture.GetAtlasInfo then
    leftInfo  = leftInfo  or C_Texture.GetAtlasInfo(ATLAS .. "-Left")
    rightInfo = rightInfo or C_Texture.GetAtlasInfo(ATLAS .. "-Right")
  end
  if not (leftInfo and rightInfo and leftInfo.width and rightInfo.width) then return false end

  hideNativeArt(btn)

  local d = { leftInfo = leftInfo, rightInfo = rightInfo }
  d.Left = btn:CreateTexture(nil, "BACKGROUND")
  d.Left:SetPoint("TOPLEFT")
  d.Right = btn:CreateTexture(nil, "BACKGROUND")
  d.Right:SetPoint("TOPRIGHT")
  d.Center = btn:CreateTexture(nil, "BACKGROUND")
  d.Center:SetHorizTile(true)
  d.Center:SetPoint("TOPLEFT",     d.Left,  "TOPRIGHT")
  d.Center:SetPoint("BOTTOMRIGHT", d.Right, "BOTTOMLEFT")
  btn._neThreeSlice = d

  -- Highlight: a 3-slice matching the body, shown on hover.
  local hi = NE.tex._atlasEntry(ATLAS .. "-Highlight")
  if hi and hi.file then
    local hiFile = NE.tex.localFiles[hi.file] or hi.file
    local L, R = hi.left or 0, hi.right or 1
    local T, B = hi.top or 0, hi.bottom or 1
    local span  = R - L
    local lFrac = (leftInfo.width  / (hi.width or 441)) * span
    local rFrac = (rightInfo.width / (hi.width or 441)) * span
    local function hlPiece(over, x0, x1)
      local t = btn:CreateTexture(nil, "ARTWORK", nil, 2)
      t:SetTexture(hiFile)
      t:SetTexCoord(x0, x1, T, B)
      t:SetAllPoints(over)
      t:SetBlendMode("ADD")
      t:Hide()
      return t
    end
    d.hl = {
      hlPiece(d.Left,   L,         L + lFrac),
      hlPiece(d.Center, L + lFrac, R - rFrac),
      hlPiece(d.Right,  R - rFrac, R),
    }
    btn:HookScript("OnEnter", function() for _, t in ipairs(d.hl) do t:Show() end end)
    btn:HookScript("OnLeave", function() for _, t in ipairs(d.hl) do t:Hide() end end)
  end

  updateButton(btn, "NORMAL")

  btn:HookScript("OnMouseDown",   function(self) updateButton(self, "PUSHED") end)
  btn:HookScript("OnMouseUp",     function(self) updateButton(self, "NORMAL") end)
  btn:HookScript("OnEnable",      function(self) updateButton(self) end)
  btn:HookScript("OnDisable",     function(self) updateButton(self) end)
  btn:HookScript("OnSizeChanged", function(self) updateScale(self) end)
  return true
end

-- ── The addon-wide sweep ────────────────────────────────────────────────────────────────────────
--
-- The red 3-slice is the addon's STANDARD button now, and this is what makes that true without
-- rewriting sixty CreateFrame calls. Nearly every button NewEra builds is a plain
-- UIPanelButtonTemplate, and on 3.3.5a that template's whole identity is one texture path: it
-- SetNormalTextures "Interface\Buttons\UI-Panel-Button-Up". So the predicate reads the art rather
-- than guessing at the template, which is the one thing a running frame can actually be asked.
--
-- Self-limiting by construction: Skin() clears that normal texture, so a skinned button no longer
-- matches, and `_neThreeSlice` short-circuits a re-skin anyway.
--
-- OPT-OUT is `_nePlain` (already the codebase's marker for "this is a plain button standing in for a
-- tab" — those live in a tab strip and would read as loose buttons in red) and `_neNoSkin` for
-- anything else that has to stay stock.

local PANEL_ART = "ui-panel-button-up"
local MAX_DEPTH = 12
local HOOK_DEPTH = 2   -- how deep Watch hooks OnShow; see below

local function isPanelButton(f)
  if not f or f._neThreeSlice or f._nePlain or f._neNoSkin then return false end
  if not (f.GetObjectType and f:GetObjectType() == "Button") then return false end
  local nt = f.GetNormalTexture and f:GetNormalTexture()
  local path = nt and nt.GetTexture and nt:GetTexture()
  if type(path) ~= "string" then return false end
  return string.find(string.lower(path), PANEL_ART, 1, true) ~= nil
end

NE.buttonskin._isPanelButton = isPanelButton   -- test seam

-- Skin every panel button under `root`. Returns how many it skinned this pass.
function NE.buttonskin.SkinPanelButtons(root, depth)
  if not (root and root.GetChildren) then return 0 end
  depth = (depth or 0) + 1
  if depth > MAX_DEPTH then return 0 end
  local n = 0
  local kids = { root:GetChildren() }
  for i = 1, #kids do
    local c = kids[i]
    if c and not c._neNoSkin then
      if isPanelButton(c) and NE.buttonskin.Skin(c) then n = n + 1 end
      n = n + NE.buttonskin.SkinPanelButtons(c, depth)
    end
  end
  return n
end

-- Keep `root` skinned as it grows. A window is registered before its contents exist, and panes are
-- built lazily on the tab that first needs them, so ONE sweep at registration would miss most of the
-- addon. Three passes cover it: now, next frame (after the caller finishes building), and on show.
--
-- OnShow is also hooked on frames near the top of the tree — that is where tab panes live, and a pane
-- built on first selection is shown immediately after, which is the moment its buttons appear. The
-- depth cap keeps that to a couple of dozen hooks per window instead of one per frame.
function NE.buttonskin.Watch(root)
  if not root or root._neSkinWatched then return end
  root._neSkinWatched = true

  local function sweep()
    NE.buttonskin.SkinPanelButtons(root)
    NE.buttonskin._HookShown(root, 0)
  end
  root._neSkinSweep = sweep

  sweep()
  if C_Timer and C_Timer.After then C_Timer.After(0, sweep) end
  if root.HookScript then
    root:HookScript("OnShow", function()
      sweep()
      if C_Timer and C_Timer.After then C_Timer.After(0, sweep) end
    end)
  end
end

function NE.buttonskin._HookShown(frame, depth)
  if depth >= HOOK_DEPTH or not (frame and frame.GetChildren) then return end
  local kids = { frame:GetChildren() }
  for i = 1, #kids do
    local c = kids[i]
    if c and c.HookScript and not c._neSkinShowHooked then
      c._neSkinShowHooked = true
      c:HookScript("OnShow", function(self)
        NE.buttonskin.SkinPanelButtons(self)
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function() NE.buttonskin.SkinPanelButtons(self) end)
        end
      end)
    end
    NE.buttonskin._HookShown(c, depth + 1)
  end
end
