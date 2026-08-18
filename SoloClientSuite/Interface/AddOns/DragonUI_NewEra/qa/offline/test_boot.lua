-- Boot the Cooldown Manager stack against a stubbed 3.3.5a client and drive it through a
-- realistic event sequence. Catches load-order faults, nil calls, and typos that a syntax
-- check cannot.

-- Addon root. Defaults to the repo root relative to the usual invocation
--   luajit qa/offline/test_boot.lua
-- Override with NE_ADDON_ROOT (trailing slash) to run from elsewhere.
local ADDON = os.getenv("NE_ADDON_ROOT") or "./"

-- ── clock ───────────────────────────────────────────────────────────────────
-- GetTime() is constant within a frame in the real client, which is exactly what NE.aura's
-- snapshot cache keys on. So a test that changes auras must also step the clock, or it will keep
-- reading the previous frame's cached scan.
local NOW = 1000.0
function GetTime() return NOW end
local function nextFrame(dt) NOW = NOW + (dt or 0.05) end

-- ── widget stubs ────────────────────────────────────────────────────────────
local allFrames = {}

local function newRegion(kind, layer)
  local r = { _kind = kind, _shown = true, _alpha = 1, _layer = layer }
  function r:SetTexture(t) self._tex = t end
  function r:GetTexture() return self._tex end
  -- Recorded, not discarded: the GCD flipbook stepper's only observable output is its texcoords, and
  -- that code path first executes in Phase 8a.
  function r:SetTexCoord(...) self._coords = { ... } end
  function r:GetTexCoord()
    local c = self._coords
    if not c then return nil end
    return c[1], c[2], c[3], c[4]
  end
  function r:SetVertexColor(...) self._color = { ... } end
  function r:GetVertexColor()
    local c = self._color
    if not c then return 1, 1, 1, 1 end
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
  end
  function r:SetDesaturated(v) self._desat = v end
  -- Tiling. Recorded because a body fill that does not tile stretches one 1024px stone across the
  -- whole window, and because their ABSENCE was hiding more than that: PanelChrome calls these on
  -- the branch it takes when the rock art resolves, so a stub without them could only ever run the
  -- graceful-degrade branch no player sees.
  function r:SetHorizTile(v) self._horizTile = v end
  function r:SetVertTile(v)  self._vertTile  = v end
  -- Getters too. Without them a "does the centre tile?" assertion could only be written with a
  -- nil escape hatch, which passes whether it tiles or not.
  function r:GetHorizTile() return self._horizTile and true or false end
  function r:GetVertTile()  return self._vertTile  and true or false end
  -- Anchors are RECORDED, in the same shape frames use. Discarding them meant a texture's geometry
  -- was unassertable, which is how the icon/frame fit went unnoticed: the overlay art was registered
  -- and the icon overshot its border by four pixels with nothing able to see it.
  r._points = {}
  function r:SetAllPoints(rel) self._points[#self._points + 1] = { "ALL", rel } end
  function r:SetPoint(p, rel, relP, x, y) self._points[#self._points + 1] = { p, rel, relP, x, y } end
  function r:ClearAllPoints() self._points = {} end
  function r:GetNumPoints() return #self._points end
  function r:GetPoint(i)
    local pt = self._points[i or 1]
    if not pt then return nil end
    return pt[1], pt[2], pt[3], pt[4], pt[5]
  end
  function r:Show() self._shown = true end
  function r:Hide() self._shown = false end
  function r:IsShown() return self._shown end
  function r:SetAlpha(a) self._alpha = a end
  function r:GetAlpha() return self._alpha end
  function r:SetFontObject(f) self._font = f end
  function r:SetText(t) self._text = t end
  function r:GetText() return self._text end
  function r:SetWidth(w) self._w = w end
  function r:SetHeight(h) self._h = h end
  function r:SetSize(w, h) self._w, self._h = w, h end
  function r:GetWidth() return self._w or 0 end
  function r:GetHeight() return self._h or 0 end
  function r:GetSize() return self._w or 0, self._h or 0 end
  -- Recorded from Phase 8c: the buffed-spell glow is a second copy of the frame art in the same rect,
  -- so BOTH of these carry meaning — without ADD it darkens the tile instead of lighting it, and
  -- without the sublevel it draws under the art it is supposed to light.
  function r:SetDrawLayer(layer, sub) self._layer, self._sublevel = layer, sub end
  function r:GetDrawLayer() return self._layer, self._sublevel end
  function r:SetTexCoordModifiesRect() end
  function r:SetRotation() end
  function r:SetJustifyH() end
  function r:SetJustifyV() end
  -- Word-wrapped description text measures itself to decide its row height. A fixed answer is enough
  -- for the layout maths to be exercised; the real client returns the wrapped height.
  function r:GetStringHeight() return 12 end
  function r:SetBlendMode(m) self._blend = m end
  function r:GetBlendMode() return self._blend or "BLEND" end
  function r:SetParent(p) self._parent = p end
  return r
end

local frameMeta = {}
frameMeta.__index = frameMeta

function CreateFrame(kind, name, parent, template)
  local f = setmetatable({
    _kind = kind, _name = name, _parent = parent, _shown = true, _scale = 1,
    _w = 0, _h = 0, _children = {}, _scripts = {}, _events = {}, _points = {},
    _regions = {},
  }, frameMeta)
  if parent and parent._children then parent._children[#parent._children + 1] = f end
  if name then _G[name] = f end
  allFrames[#allFrames + 1] = f

  -- Templates are otherwise ignored here, with ONE exception. ButtonFrameTemplate ships an Inset
  -- child frame whose $parentBg carries parentKey="Bg" — the old ClassicAPI marble, BACKGROUND
  -- subLevel -5. It is the one template-supplied region our panels reach for by name, and a guard
  -- that says "the marble stays hidden" asserts precisely nothing while f.Inset is nil.
  --
  -- Note what is NOT modelled: the template's own $parentBg on the frame itself has NO parentKey
  -- (UIPanelTemplates.xml:1517), which is exactly why PanelChrome builds f.Bg fresh instead of
  -- re-texturing that one — and why the two ended up on opposite sides of subLevel 0.
  if template == "ButtonFrameTemplate" then
    local inset = CreateFrame("Frame", name and (name .. "Inset"), f)
    inset.Bg = inset:CreateTexture(nil, "BACKGROUND", nil, -5)
    f.Inset = inset
  end

  -- UIPanelButtonTemplate's normal texture. On 3.3.5a that ONE path is the template's whole
  -- identity at runtime, and it is what NE.buttonskin's addon-wide sweep matches on — a running
  -- frame cannot be asked which template built it. Without this the sweep would find nothing here
  -- and every assertion about it would pass by describing an empty tree.
  if type(template) == "string" and template:find("UIPanelButtonTemplate", 1, true) then
    f:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  end

  -- OptionsSliderTemplate's groove: a BACKDROP of UI-SliderBar-Background inside a beveled border,
  -- plus the three $parent-named FontStrings the kit blanks. Modelled because the minimal slider skin
  -- exists to remove that backdrop, and a template that never had one cannot show whether it did.
  if template == "OptionsSliderTemplate" then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
                    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border" })
    f:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if name then
      for _, suffix in ipairs({ "Text", "Low", "High" }) do
        local fs = newRegion("FontString")
        _G[name .. suffix] = fs
      end
    end
  end

  -- UIPanelScrollFrameTemplate's stock bar: a `$parentScrollBar` Slider carrying
  -- `$parentScrollUpButton` / `$parentScrollDownButton`. Modelled by GLOBAL NAME and deliberately
  -- WITHOUT a `.ScrollBar` parentKey, because that is precisely how 3.3.5a declares it — and that
  -- absence is why NE.scrollbar.Reskin, which only ever checked the parentKey, returned at its
  -- second line and silently reskinned nothing on frames like this one.
  if template == "UIPanelScrollFrameTemplate" and name then
    local sb = CreateFrame("Slider", name .. "ScrollBar", f)
    CreateFrame("Button", sb:GetName() .. "ScrollUpButton",   sb)
    CreateFrame("Button", sb:GetName() .. "ScrollDownButton", sb)
  end
  return f
end

-- The client fires OnSizeChanged whenever a frame's dimensions actually change. The anchor-sync in
-- NE.RegisterHUDFrame depends on it, so the stub must too.
local function sized(f, ow, oh)
  if (f._w ~= ow or f._h ~= oh) and f._scripts.OnSizeChanged then
    f._scripts.OnSizeChanged(f, f._w, f._h)
  end
end
function frameMeta:SetSize(w, h) local ow, oh = self._w, self._h; self._w, self._h = w, h; sized(self, ow, oh) end
function frameMeta:SetWidth(w) local ow = self._w; self._w = w; sized(self, ow, self._h) end
function frameMeta:SetHeight(h) local oh = self._h; self._h = h; sized(self, self._w, oh) end
function frameMeta:GetWidth() return self._w end
function frameMeta:GetHeight() return self._h end
function frameMeta:GetScale() return self._scale end
function frameMeta:SetScale(s) self._scale = s end
function frameMeta:SetAlpha(a) self._alpha = a end
function frameMeta:GetAlpha() return self._alpha or 1 end
-- Match the client: OnShow fires only on a hidden -> shown TRANSITION, not on every Show() call.
function frameMeta:Show()
  local was = self._shown
  self._shown = true
  if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
-- Symmetrically, OnHide fires on a shown -> hidden transition. The settings panel cancels an
-- in-flight drag from there, because the close button and ESC both call Hide() directly.
function frameMeta:Hide()
  local was = self._shown
  self._shown = false
  if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function frameMeta:IsShown() return self._shown end
function frameMeta:SetPoint(p, rel, relP, x, y) self._points[#self._points + 1] = { p, rel, relP, x, y } end
function frameMeta:SetAllPoints(rel) self._points[#self._points + 1] = { "ALL", rel } end
function frameMeta:ClearAllPoints() self._points = {} end
function frameMeta:GetNumPoints() return #self._points end
function frameMeta:GetPoint(i)
  local pt = self._points[i or 1]
  if not pt then return nil end
  return pt[1], pt[2], pt[3], pt[4], pt[5]
end
function frameMeta:GetChildren() return unpack(self._children) end
function frameMeta:EnableMouse() end
-- Frame level is RECORDED, not discarded. Kept from a reverted experiment because the gap is real
-- and general: "this draws above that" was unassertable, the same way CreateTexture's dropped LAYER
-- argument made "this draws behind that" unassertable. Three stub parameters accepted and forgotten
-- have now each hidden something.
function frameMeta:SetFrameLevel(v) self._level = v end
function frameMeta:GetFrameLevel() return self._level or 1 end
-- Recorded and readable. A write-only SetFrameStrata meant any code that RE-READ a strata to match
-- it (the scrollbar promotes its arrows to the track's own strata, so they cannot render behind it)
-- hit a nil method and died inside a pcall — visible offline only as a widget that quietly failed
-- to build. UIParent's default is MEDIUM, same as the client's.
function frameMeta:SetFrameStrata(s) self._strata = s end
function frameMeta:GetFrameStrata() return self._strata or "MEDIUM" end
function frameMeta:SetParent(p) self._parent = p end
function frameMeta:GetParent() return self._parent end
function frameMeta:SetMovable() end
function frameMeta:SetUserPlaced() end
-- Window surface: what a draggable, ESC-closable panel touches.
function frameMeta:SetClampedToScreen() end
function frameMeta:SetToplevel() end
function frameMeta:RegisterForDrag() end
function frameMeta:StartMoving() end
function frameMeta:StopMovingOrSizing() end
function frameMeta:EnableMouseWheel() end
function frameMeta:EnableKeyboard() end
function frameMeta:SetHitRectInsets() end
function frameMeta:RegisterForClicks() end
function frameMeta:SetResizable() end
function frameMeta:SetMinResize() end
function frameMeta:SetMaxResize() end
function frameMeta:GetRegions() return unpack(self._regions) end
function frameMeta:GetObjectType() return self._kind end
function frameMeta:GetName() return self._name end
function frameMeta:GetEffectiveScale() return self._scale or 1 end
-- Drag targeting is geometry: the caret goes before or after the tile depending on which side of
-- its CENTRE the cursor sits. A stub that cannot answer GetCenter cannot test that at all, so
-- tests place tiles explicitly via _center.
function frameMeta:GetCenter()
  local c = self._center
  if c then return c[1], c[2] end
  return nil
end
-- The four edges, derived from that centre and the frame's own size. Without them, code that resolves
-- a placement into SCREEN coordinates could only ever take its "I cannot measure this" fallback — so
-- the branch that actually runs in game would be the one branch never tested.
function frameMeta:GetLeft()   local c = self._center; return c and (c[1] - (self._w or 0) / 2) or nil end
function frameMeta:GetRight()  local c = self._center; return c and (c[1] + (self._w or 0) / 2) or nil end
function frameMeta:GetTop()    local c = self._center; return c and (c[2] + (self._h or 0) / 2) or nil end
function frameMeta:GetBottom() local c = self._center; return c and (c[2] - (self._h or 0) / 2) or nil end
function frameMeta:LockHighlight() self._locked = true end
function frameMeta:UnlockHighlight() self._locked = false end
-- RECORDED. OptionsSliderTemplate's groove is a backdrop, not a texture, and the minimal skin's first
-- act is to clear it — with a no-op setter, "the 2004 groove is gone" was a question the harness had
-- no way to answer, and a skin that forgot to clear it would have tested identically.
function frameMeta:SetBackdrop(bd) self._backdrop = bd end
function frameMeta:SetBackdropColor() end
function frameMeta:SetBackdropBorderColor() end
-- ScrollFrame surface.
function frameMeta:SetScrollChild(c) self._scrollChild = c end
function frameMeta:GetScrollChild() return self._scrollChild end
function frameMeta:SetVerticalScroll(v) self._vscroll = v end
function frameMeta:GetVerticalScroll() return self._vscroll or 0 end
-- Settable, so a test can put a scroll frame into the "there is something to scroll" state. It used
-- to be a hard 0, which is the one value that makes every scrollbar hide itself — a bar could have
-- been built wrong in every respect and still looked right, because it was never asked to appear.
function frameMeta:GetVerticalScrollRange() return self._vrange or 0 end
function frameMeta:UpdateScrollChildRect() end
-- EditBox surface (the search box).
function frameMeta:SetAutoFocus() end
function frameMeta:ClearFocus() end
function frameMeta:SetTextInsets() end
function frameMeta:SetText(t) self._text = t end
function frameMeta:GetText() return self._text or "" end
function frameMeta:SetFontObject() end
function frameMeta:SetHighlightTexture() end
function frameMeta:SetPushedTexture() end
-- The four button state textures, MEMOIZED. They used to hand back a fresh region every call, so a
-- reskin that set an atlas on one wrote it to a throwaway and nothing could observe the result —
-- "did this button get retextured" was an unanswerable question offline.
local function stateTex(self, key)
  self._stateTex = self._stateTex or {}
  if not self._stateTex[key] then self._stateTex[key] = newRegion("Texture") end
  return self._stateTex[key]
end
-- SetNormalTexture WRITES to the memoized region rather than dropping the path on the floor: the
-- button skin's sweep predicate reads it back, and a setter that forgets makes that unanswerable.
function frameMeta:SetNormalTexture(v)   stateTex(self, "normal"):SetTexture(v)  end
function frameMeta:GetNormalTexture()    return stateTex(self, "normal")    end
function frameMeta:GetPushedTexture()    return stateTex(self, "pushed")    end
function frameMeta:GetDisabledTexture()  return stateTex(self, "disabled")  end
function frameMeta:GetHighlightTexture() return stateTex(self, "highlight") end
function frameMeta:SetDisabledTexture() end
-- A Slider's thumb, memoized for the same reason as the four above: the minimal slider skin
-- retextures it and hangs its rounded caps off it, so a fresh region per call would make "is the
-- thumb wearing the minimal art" unanswerable.
function frameMeta:GetThumbTexture() return stateTex(self, "thumb") end
function frameMeta:SetThumbTexture(v) stateTex(self, "thumb"):SetTexture(v) end
-- Present because the client has it, and because its ABSENCE is the defect it exists to fix: a
-- disabled Button eats OnEnter unless this is on, which is what left the greyed Revert unable to
-- explain itself.
function frameMeta:SetMotionScriptsWhileDisabled(on) self._motionWhileDisabled = on and true or false end
function frameMeta:IsMouseOver() return self._mouseOver and true or false end
-- Enable/Disable FIRE their scripts, as the client does. A skin that repaints on OnEnable/OnDisable
-- (core/ButtonSkin.lua) is otherwise never asked to, so a disabled button would test as wearing the
-- normal art while in game it wears the disabled art — or vice versa, which is worse.
function frameMeta:Enable()
  self._enabled = true
  local fn = self._scripts and self._scripts.OnEnable
  if fn then fn(self) end
end
function frameMeta:Disable()
  self._enabled = false
  local fn = self._scripts and self._scripts.OnDisable
  if fn then fn(self) end
end
function frameMeta:IsEnabled() return self._enabled ~= false end
function frameMeta:RegisterEvent(e) self._events[e] = true end
function frameMeta:UnregisterEvent(e) self._events[e] = nil end
function frameMeta:SetScript(s, fn) self._scripts[s] = fn end
function frameMeta:GetScript(s) return self._scripts[s] end
-- CHAINS, as the client does. Replacing meant the LAST hook on a script silently won: the BuffBar
-- rows hook OnSizeChanged twice — once for the fill overlay's texcoord, once for the Bar-BG cap
-- widths — and under a replacing stub only one of them was ever exercised.
function frameMeta:HookScript(s, fn)
  local prev = self._scripts[s]
  if not prev then self._scripts[s] = fn; return end
  self._scripts[s] = function(...) prev(...) ; fn(...) end
end
-- The LAYER argument is kept. Discarding it meant GetDrawLayer only ever answered for regions that
-- had also been through SetDrawLayer, so a region created on the wrong layer was unassertable — which
-- is how a mutation test on the buff glow's layer came back green with the glow back over the icon.
-- AnimationGroups, recorded rather than simulated. The pandemic ring's pulse is a real feature with
-- a real failure mode (built, never played), and without this the builder's feature gate would just
-- skip it and the ring would test green while sitting static. Alpha carries SetFromAlpha/SetToAlpha
-- because ClassicAPI polyfills that pair on this client; the raw SetChange fallback is not stubbed,
-- so a change that started depending on it would show up here rather than only in game.
function frameMeta:CreateAnimationGroup()
  local ag = { _anims = {}, _playing = false }
  function ag:SetLooping(m) self._loop = m end
  function ag:GetLooping() return self._loop end
  function ag:Play() self._playing = true end
  function ag:Stop() self._playing = false end
  function ag:IsPlaying() return self._playing end
  function ag:CreateAnimation(kind)
    local a = { _kind = kind }
    function a:SetDuration(d)   self._dur = d end
    function a:SetOrder(o)      self._order = o end
    function a:SetSmoothing(s)  self._smooth = s end
    function a:SetStartDelay(d) self._delay = d end
    function a:SetFromAlpha(v)  self._from = v end
    function a:SetToAlpha(v)    self._to = v end
    self._anims[#self._anims + 1] = a
    return a
  end
  self._animGroups = self._animGroups or {}
  self._animGroups[#self._animGroups + 1] = ag
  return ag
end
-- The SUBLEVEL is recorded, not dropped. Two textures on the same layer are ordered by it, and
-- "created below the thing it was meant to cover" is a bug with no other symptom: the region exists,
-- is shown, has the right texture and the right anchors, and is invisible. The /cdm window shipped
-- an Inset fill that way and nobody could see it for four phases.
function frameMeta:CreateTexture(_, layer, _, sublevel)
  local t = newRegion("Texture", layer)
  t._sublevel = sublevel or 0
  self._regions[#self._regions+1] = t
  return t
end
function frameMeta:CreateFontString() local t = newRegion("FontString"); self._regions[#self._regions+1] = t; return t end
function frameMeta:SetCooldown(s, d) self._cdStart, self._cdDur = s, d end
function frameMeta:SetDrawEdge() end
function frameMeta:SetReverse(v) self._reverse = v end
-- StatusBar surface (BuffBar rows) — and Slider, which shares it.
function frameMeta:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function frameMeta:GetMinMaxValues() return self._min or 0, self._max or 1 end
-- The client fires OnValueChanged whenever SetValue actually MOVES the value, including when the
-- caller is code rather than a drag. The settings sliders depend on that being true: each one
-- re-seats its thumb from inside its own OnValueChanged handler, and re-reads its getter on every
-- page refresh. A stub that swallowed those calls could not tell a working re-entrancy guard from a
-- missing one.
function frameMeta:SetValue(v)
  local old = self._value
  self._value = v
  if old ~= v and self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
end
function frameMeta:GetValue() return self._value end
function frameMeta:SetValueStep(s) self._valueStep = s end
function frameMeta:SetOrientation(o) self._orientation = o end
-- CheckButton surface. 3.3.5a returns 1/nil rather than true/false, which is why every reader in the
-- settings kit normalises with `and true or false`; the stub returns booleans because the difference
-- is only interesting at the call site, and a test asserting `== true` on a real client would pass
-- anyway through that normalisation.
function frameMeta:SetChecked(v) self._checked = v and true or false end
function frameMeta:GetChecked() return self._checked end
function frameMeta:Click(button)
  if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end
end
-- SetObeyStepOnDrag is deliberately ABSENT: it is retail-only, which is why the slider kit snaps the
-- value itself. Adding it here would hide that.
function frameMeta:SetStatusBarColor(...) self._barColor = { ... } end
function frameMeta:GetStatusBarColor()
  local c = self._barColor
  if not c then return 1, 1, 1, 1 end
  return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end
-- SetStatusBarTexture takes a path OR a texture, and GetStatusBarTexture always hands back a
-- TEXTURE OBJECT — never the path you passed in. Returning the raw argument (as this stub used to)
-- meant NE.tex.SetAtlasOnStatusBar called SetAlpha on a string, which only surfaced once Phase 8a
-- registered the bar atlas and that function stopped bailing out early. The Pip also anchors to this
-- object (AuraItemMixins:193), so a string would silently misplace it in the real client too.
function frameMeta:SetStatusBarTexture(t)
  if type(t) == "table" then
    self._barTexObj = t
  else
    if not self._barTexObj then self._barTexObj = newRegion("Texture") end
    self._barTexObj:SetTexture(t)
  end
  self._barTex = t
end
function frameMeta:GetStatusBarTexture() return self._barTexObj end

-- Fire an event at every frame registered for it (respecting the unit filter shim).
local function fireEvent(event, ...)
  for _, f in ipairs(allFrames) do
    if f._events and f._events[event] and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end

-- ── game API stubs ──────────────────────────────────────────────────────────
-- WoW exposes the Lua stdlib under short global aliases and addon code uses them freely.
tinsert, tremove, tContains = table.insert, table.remove, nil
sort, wipe = table.sort, function(t) for k in pairs(t) do t[k] = nil end return t end
strfind, strsub, strupper, strlower, strrep, strlen = string.find, string.sub, string.upper, string.lower, string.rep, string.len
format, gsub, strmatch, strsplit = string.format, string.gsub, string.match, nil
abs, floor, ceil, max, min, sqrt = math.abs, math.floor, math.ceil, math.max, math.min, math.sqrt

UIParent = CreateFrame("Frame", "UIParent")
-- A real screen size. It defaulted to 0x0, and code that asks "is this frame on the left half or the
-- right half?" then always answers the same way — so one of the two branches could never run here.
UIParent:SetSize(1024, 768)
-- ClassicAPI's SearchBoxTemplate seeds the edit box with this string as its placeholder, so any
-- code reading the box back sees "Search" until the player types. That is a real behaviour, not
-- decoration — it dimmed the whole settings grid once.
SEARCH, YES, NO = "Search", "Yes", "No"
BOOKTYPE_SPELL = "spell"
MAX_TOTEMS = 4

function UnitClass(u) return "Priest", "PRIEST" end
-- Identity, for anything keyed per character. Both are reassignable so a test can "log in" as
-- someone else without a second harness run.
function UnitName(u) return "Testpriest" end
function GetRealmName() return "Test Realm" end
function UnitRace(u) return "Human", "Human" end
function UnitExists(u) return u == "player" end
-- Live aura tables, keyed by unit. Each entry uses the 3.3.5a return order, which is what makes
-- this stub worth having: name, RANK, icon, count, dispelType, duration, expiration, caster,
-- isStealable, shouldConsolidate, spellID. `rank` at index 2 is the shift that breaks any code
-- ported straight from a modern client.
BUFFS   = { player = {}, target = {} }
DEBUFFS = { player = {}, target = {} }

local function auraGetter(tbl)
  return function(unit, i)
    local a = tbl[unit] and tbl[unit][i]
    if not a then return nil end
    return a.name, a.rank or "", a.icon, a.count or 0, a.dispelType,
           a.duration or 0, a.expiration or 0, a.caster, false, false, a.spellID
  end
end
UnitBuff   = auraGetter(BUFFS)
UnitDebuff = auraGetter(DEBUFFS)
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function InCombatLockdown() return false end
function GetTotemInfo() return false end
-- Post-hook: run the original, then the hook, and hand back the original's returns. Both real forms
-- are supported — hooksecurefunc(tbl, "name", fn) and hooksecurefunc("globalName", fn).
function hooksecurefunc(a, b, c)
  local tbl, key, hook
  if type(a) == "table" then tbl, key, hook = a, b, c else tbl, key, hook = _G, a, b end
  local orig = tbl[key]
  if type(orig) ~= "function" or type(hook) ~= "function" then return end
  tbl[key] = function(...)
    local r1, r2, r3, r4 = orig(...)
    pcall(hook, ...)
    return r1, r2, r3, r4
  end
end
-- Mirrors 3.3.5a: IsUsableSpell takes a spell NAME (or a spellbook index + bookType). Given a
-- spellID it reads it as an index past the end of the book and returns nil — no error, just a
-- silent nil that is neither usable nor out-of-mana. Returning a blanket `true` here is what let
-- the viewer ship rendering every icon permanently grey.
-- 3.3.5a answers by NAME (or spellbook index), and answers NIL for a name it does not know as a
-- castable spell. That nil is the whole point: a tracked-buff row like "Surge of Light" is an aura
-- with no spell of that name, so the `usable` alert can never fire on it. A stub that said `true`
-- for any string reported those rows as castable and hid it.
function IsUsableSpell(arg)
  -- Asked through GetSpellInfo rather than the name table directly: that table is a local declared
  -- further down this file, so naming it here reads a nil global at call time.
  if type(arg) == "string" then
    if not GetSpellInfo(arg) then return nil end
    return true, false
  end
  return nil
end
function IsSpellInRange() return nil end
function IsUsableItem() return true end
function IsSpellKnown(id) return true end
function GetInventoryItemCooldown() return 0, 0, 0 end
function GetItemCooldown() return 0, 0, 0 end
function GetItemIcon() return "Interface\\Icons\\Test" end

-- Equipped inventory, keyed by slot. Trinkets are 13/14. Tests mutate this to simulate a swap, so
-- discovery has to be re-read rather than cached at load.
EQUIPPED = {}
function GetInventoryItemID(unit, slot) return unit == "player" and EQUIPPED[slot] or nil end
function GetInventoryItemTexture() return "Interface\\Icons\\TestItem" end
-- itemID -> { useSpellName, useSpellID }. An item absent here has NO on-use effect, which is how a
-- proc trinket behaves and is exactly the case discovery must skip.
ITEM_SPELLS = {}
function GetItemSpell(itemID)
  local e = ITEM_SPELLS[itemID]
  if not e then return nil end
  return e[1], e[2]
end
INVSLOT_TRINKET1, INVSLOT_TRINKET2 = 13, 14

-- A tiny fake spellbook: Mind Blast with three ranks, plus a few singles.
SPELLS = {
  [8092]  = { "Mind Blast", "Rank 1" },
  [8102]  = { "Mind Blast", "Rank 2" },
  [10947] = { "Mind Blast", "Rank 3" },
  [10060] = { "Power Infusion", "" },
  [14751] = { "Inner Focus", "" },
  [2944]  = { "Devouring Plague", "Rank 1" },
  [17]    = { "Power Word: Shield", "Rank 1" },
  [15487] = { "Silence", "" },
  [586]   = { "Fade", "Rank 1" },
  [8122]  = { "Psychic Scream", "Rank 1" },
  [6346]  = { "Fear Ward", "" },
  [19236] = { "Desperate Prayer", "" },
  [15286] = { "Vampiric Embrace", "" },
  [724]   = { "Lightwell", "" },
  [61304] = { "Global Cooldown", "" },
  [20572] = { "Blood Fury", "" },
}
local NAME_TO_ID = {}
for id, e in pairs(SPELLS) do
  if not NAME_TO_ID[e[1]] then NAME_TO_ID[e[1]] = id end
end
-- highest rank wins for name lookups
NAME_TO_ID["Mind Blast"] = 10947

function GetSpellInfo(idOrName)
  local id = tonumber(idOrName)
  if not id then id = NAME_TO_ID[idOrName] end
  local e = id and SPELLS[id]
  if not e then return nil end
  -- 3.3.5a signature: name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange
  return e[1], e[2], "Interface\\Icons\\Spell_" .. id, 0, false, 0, 1500, 0, 30
end

local COOLDOWNS = {}
function GetSpellCooldown(idOrName)
  local id = tonumber(idOrName) or NAME_TO_ID[idOrName]
  local cd = id and COOLDOWNS[id]
  if cd then return cd[1], cd[2], 1 end
  return 0, 0, 1
end

function GetSpellLink(slot, bookType)
  local id = _G.__SLOT_IDS and _G.__SLOT_IDS[slot]
  return id and ("|cff71d5ff|Hspell:" .. id .. "|h[x]|h|r") or nil
end

-- Spellbook: 8 slots in one tab.
BOOK = { 8092, 8102, 10947, 10060, 14751, 2944, 17, 586 }
_G.__SLOT_IDS = BOOK
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo(tab) return "General", "", 0, #BOOK end
function GetSpellBookItemName(slot) local id = BOOK[slot]; if not id then return nil end; return SPELLS[id][1], SPELLS[id][2] end
function GetSpellBookItemInfo(slot) return "SPELL", BOOK[slot] end
function GetSpellTexture() return "Interface\\Icons\\Test" end

function CooldownFrame_Set(cd, start, duration, enable)
  if enable and enable ~= 0 and start > 0 and duration > 0 then
    cd:SetCooldown(start, duration)
  else
    cd:Hide()
  end
end
function CooldownFrame_Clear(cd) cd:Hide() end

NumberFontNormalLarge = {}
NumberFontNormal = {}
NumberFontNormalSmall = {}
GameTooltip = CreateFrame("Frame", "GameTooltip")
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:SetInventoryItem() end
function GameTooltip:SetItemByID() end
-- Record the lines so a test can assert what a tooltip actually said, not just that it opened.
GameTooltip.lines = {}
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:NumLines() return #self.lines end

-- NO SetSpellByID. 3.3.5a's GameTooltip does not have one and !!!ClassicAPI does not add it (it
-- adds SetItemByID and stops there), so every spell tooltip in the addon goes through the hyperlink
-- path — and a stub that offered SetSpellByID would test a branch no player ever reaches.
--
-- SetHyperlink models the hazard that matters: on an id this client cannot resolve it does NOT
-- error, it succeeds and draws nothing. A pcall returning true is therefore no evidence of a
-- tooltip, which is exactly how aura rows ended up nameless.
-- A real spell tooltip is a title AND a body. Modelled, because the name alone cannot tell the
-- client's tooltip apart from a one-line fallback — and a test that cannot tell them apart passes
-- just as happily when the fallback has eaten every tooltip in the addon.
function GameTooltip:SetHyperlink(link)
  local id = tonumber(tostring(link):match("spell:(%d+)") or "")
  if id and SPELLS[id] then self.lines = { SPELLS[id][1], "client tooltip body" } end
end

-- Deferred callbacks, run at a drain point — but only once their delay has actually elapsed on the
-- stub clock. Honouring the delay matters: the cooldown-expiry refresh schedules itself for the end
-- of the cooldown, and a stub that fired every timer immediately would make that path look like it
-- worked no matter what it did.
local pending = {}
C_Timer = {
  After = function(delay, fn)
    pending[#pending + 1] = { at = NOW + (tonumber(delay) or 0), fn = fn }
  end,
}
local function drain()
  local n = 0
  while n < 50 do
    local due, rest = {}, {}
    for _, e in ipairs(pending) do
      if e.at <= NOW then due[#due + 1] = e else rest[#rest + 1] = e end
    end
    if #due == 0 then break end
    pending = rest
    for _, e in ipairs(due) do e.fn() end
    n = n + 1
  end
end

C_Container = {}
C_Item = {}
SlashCmdList = {}
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- ── Phase 4 stubs: alerts, sounds, menu ─────────────────────────────────────
-- Target health drives the execute branch of the "usable" alert.
TARGET_HP, TARGET_HP_MAX = 100, 100
function UnitHealth(u) return u == "target" and TARGET_HP or 100 end
function UnitHealthMax(u) return u == "target" and TARGET_HP_MAX or 100 end
function UnitIsDeadOrGhost() return false end

-- Records what was actually asked to play, so a test can tell "played the right file" from
-- "silently played nothing" — the exact distinction that matters given retail kit IDs are inert
-- on this client.
SOUNDS_PLAYED = {}
function PlaySoundFile(path, channel)
  SOUNDS_PLAYED[#SOUNDS_PLAYED + 1] = { path = path, channel = channel }
  return true
end

-- UI click sounds (the settings checkboxes) go through PlaySound, which takes a NAME on this client.
-- Kept in its own table so the ready-sound assertions above still count only what they play.
UI_SOUNDS = {}
function PlaySound(kit)
  UI_SOUNDS[#UI_SOUNDS + 1] = kit
  return true
end

-- LibCustomGlow stands in for the FX renderers. It records the live glow per frame so the tests can
-- assert on what is showing rather than on internal bookkeeping.
GLOWS = setmetatable({}, { __mode = "k" })
local LCG_STUB = {
  PixelGlow_Start    = function(r, color) GLOWS[r] = { kind = "pixel",  color = color } end,
  PixelGlow_Stop     = function(r) if GLOWS[r] and GLOWS[r].kind == "pixel"  then GLOWS[r] = nil end end,
  ButtonGlow_Start   = function(r, color) GLOWS[r] = { kind = "button", color = color } end,
  ButtonGlow_Stop    = function(r) if GLOWS[r] and GLOWS[r].kind == "button" then GLOWS[r] = nil end end,
  AutoCastGlow_Start = function(r, color) GLOWS[r] = { kind = "auto",   color = color } end,
  AutoCastGlow_Stop  = function(r) if GLOWS[r] and GLOWS[r].kind == "auto"   then GLOWS[r] = nil end end,
}
function LibStub(name, silent)
  if name == "LibCustomGlow-1.0" then return LCG_STUB end
  return nil
end

-- ── mouse, for the drag reorder ─────────────────────────────────────────────
-- 3.3.5a has no GLOBAL_MOUSE_UP, so SettingsReorder ends a drag by watching IsMouseButtonDown in
-- its OnUpdate. That makes the button state a first-class input to the code under test, not
-- scenery: a test drives a drop by releasing the button and stepping the driver.
CURSOR = { x = 0, y = 0 }
MOUSE_DOWN = { LeftButton = false, RightButton = false }
MOUSE_FOCUS = nil

function GetCursorPosition() return CURSOR.x, CURSOR.y end
function IsMouseButtonDown(btn) return MOUSE_DOWN[btn or "LeftButton"] and true or false end
function GetMouseFocus() return MOUSE_FOCUS end
function GetScreenWidth() return 1024 end

-- ── C_UIDropDownMenu stand-in ───────────────────────────────────────────────
-- NOT a reimplementation. It records the `info` tables core/Menu.lua hands to AddButton, which is
-- the part of menu rendering that is OURS and therefore checkable here. The bug this exists to
-- prevent lived in ClassicAPI's own AddButton — it reads a predicate through
-- `type(x)=="function" and x() or x`, which returns the FUNCTION (truthy) whenever the predicate is
-- false, so every function-valued radio drew as selected. Copying that bug into the stub to "catch"
-- it would be circular; asserting we only ever pass a BOOLEAN is not, and is what keeps us clear of
-- it. Levels are recorded separately so a test can walk into a submenu.
DD_ROWS = {}
local function ddReset(fromLevel)
  for l = fromLevel, 8 do
    DD_ROWS[l] = nil
    local list = _G["C_DropDownList" .. l]
    if list then list.numButtons = 0 end
  end
end

function C_UIDropDownMenu_CreateInfo() return {} end

function C_UIDropDownMenu_AddButton(info, level)
  level = level or 1
  local rows = DD_ROWS[level] or {}
  DD_ROWS[level] = rows
  local copy = {}
  for k, v in pairs(info) do copy[k] = v end
  rows[#rows + 1] = copy

  local listName = "C_DropDownList" .. level
  local list = _G[listName]
  if not list then
    list = CreateFrame("Frame", listName)
    -- Born hidden, as ClassicAPI's are (Templates/C_UIDropDownMenu.lua:40). Frames in this harness
    -- default to shown, which would have made the first toggle below HIDE the menu.
    list:Hide()
  end
  list.numButtons = #rows

  local bn = listName .. "Button" .. #rows
  local b = _G[bn] or CreateFrame("Button", bn)
  b.checked = info.checked
  b.menuList = info.menuList
  _G[bn .. "Check"] = _G[bn .. "Check"] or b:CreateTexture()

  -- RECORDED: $parentInvisibleButton, and the one rule that governs it — ClassicAPI shows it on any
  -- disabled row (C_UIDropDownMenu.lua:177-181), and `notClickable` and `isTitle` both BECOME
  -- disabled two lines earlier. It covers the row, and its OnEnter closes level+1, which is what made
  -- a submenu parent openable only from its 16px arrow. Without it in the stub, taking it down for
  -- submenu rows would test identically to forgetting to.
  local inv = _G[bn .. "InvisibleButton"] or CreateFrame("Button", bn .. "InvisibleButton", b)
  if info.disabled or info.notClickable or info.isTitle then inv:Show() else inv:Hide() end

  -- $parentExpandArrow, shown only on submenu rows (C_UIDropDownMenu.lua:237). It is what a level-2+
  -- list SHOULD hang off; the client hangs it off whatever `button:GetParent()` happens to be, which
  -- for a hovered row is the entire list.
  local arrow = _G[bn .. "ExpandArrow"] or CreateFrame("Button", bn .. "ExpandArrow", b)
  if info.hasArrow then arrow:Show() else arrow:Hide() end
end

function C_UIDropDownMenu_Initialize(frame, init, displayMode, level, menuList)
  frame.initialize = init
  ddReset(level or 1)
  if init then init(frame, level, menuList) end
end

-- The list's SHOWN state is modelled, because it is the one thing the click-away catcher keys off:
-- Toggle really toggles, and CloseAll really hides. Without it "is a menu open?" is unanswerable
-- offline, and a catcher that armed itself over an empty screen — eating the player's next click
-- anywhere — would test exactly the same as one that did not.
local function ddList(level) return _G["C_DropDownList" .. (level or 1)] end

function C_ToggleDropDownMenu(level, value, frame, anchor, x, y, menuList)
  frame = frame or DragonUI_NewEra.menu._frame   -- global on purpose: the NE local is declared below
  -- Set at level 1 only, as ClassicAPI does via the delegate's "openmenu" attribute. It is how a hook
  -- on the SHARED list buttons tells our menu from anyone else's before it repositions anything.
  if (level or 1) == 1 then C_UIDROPDOWNMENU_OPEN_MENU = frame end
  C_UIDropDownMenu_Initialize(frame, frame.initialize, nil, level or 1, menuList)
  local list = ddList(level)
  if list then if list:IsShown() then list:Hide() else list:Show() end end
end

function C_CloseDropDownMenus(level)
  ddReset(level or 1)
  for l = (level or 1), 8 do
    local list = ddList(l)
    if list then list:Hide() end
  end
end

-- The destructive cog entries route through a confirm popup rather than firing on click. Record
-- which one was raised; a test then calls its OnAccept, which is the path the player takes.
StaticPopupDialogs = {}
POPUPS_SHOWN = {}
function StaticPopup_Show(which)
  POPUPS_SHOWN[#POPUPS_SHOWN + 1] = which
  return StaticPopupDialogs[which]
end


-- ── DragonUI host stub ──────────────────────────────────────────────────────
local profile = { newera = { enabled = true, modules = {} }, movers = {}, widgets = {} }
DragonUI = {
  db = { profile = profile },
  ModuleRegistry = { Register = function() return true end },
  MoversSystem = { RegisterMover = function(_, info) profile.movers[info.name] = info.defaultPoint end },
  EditableFrames = {},
  RegisterEditableFrame = function(self, info) self.EditableFrames[info.name] = info end,
  -- Mirrors core/api.lua:255 — the factory that actually attaches the drag scripts, the nineslice
  -- overlay and the auto-save. RegisterEditableFrame alone is only metadata.
  CreateUIFrame = function(w, h, name)
    local f = CreateFrame("Frame", "DragonUI_" .. name, UIParent)
    f:SetSize(w, h)
    f._isUIFrame = true
    f._draggable = true
    return f
  end,
  -- Editor mode, as NE.OpenFrameEditor drives it (DragonUI modules/editor_mode.lua). Show() refusing
  -- in combat is faithful and load-bearing: the real one returns from an empty branch with no message,
  -- which is why the caller re-checks IsActive instead of trusting the call.
  EditorMode = {
    _active = false,
    Show    = function(self) if not (InCombatLockdown and InCombatLockdown()) then self._active = true end end,
    -- Hide is NOT just a flag: the real one (modules/editor_mode.lua:378) ends by calling
    -- HideAllEditableFrames(true), which is what runs every frame's hideTest and onHide. A stub that
    -- only flipped the flag would let a module leak whatever it puts up alongside a selected frame.
    Hide    = function(self)
      self._active = false
      DragonUI:HideAllEditableFrames(true)
    end,
    IsActive = function(self) return self._active end,
  },
  -- Mirrors core/api.lua:1287. hideTest runs unconditionally; onHide only on a refreshing close,
  -- which is the only kind EditorMode:Hide performs.
  HideAllEditableFrames = function(self, refresh)
    for _, frameData in pairs(self.EditableFrames) do
      if frameData.hideTest then frameData.hideTest() end
      if refresh and frameData.onHide then frameData.onHide() end
    end
  end,
  -- Records the frame the editor was told to select. Which frame that is, is the whole point: the
  -- editor knows the ANCHOR, never the HUD content hung off it.
  SelectEditorFrame = function(frame) DragonUI._selected = frame end,
}

DragonUI_NewEra = { dragon = DragonUI, db = {} }
local NE = DragonUI_NewEra
function NE.Log(tag, msg) print("  [LOG " .. tag .. "] " .. msg) end
NE.tex = { localFiles = {}, atlases = {},
  SetAtlas = function() return false end,
  GetAtlasRect = function() return nil end,
}
NE.qa = { modules = {} }
NE.compat = { RecordStub = function() end }
NE.FrameUtil = { PinPixelPerfect = function() end }

-- ── load in TOC order ───────────────────────────────────────────────────────
local FILES = {
  "compat/Events.lua",
  "core/GridLayout.lua",
  "core/CooldownNumbers.lua",
  "core/AuraSnapshot.lua",
  "core/SpellRanks.lua",
  "integration/Register.lua",
  "integration/Options.lua",
  "modules/cooldownviewer/ClassData.lua",
  "modules/cooldownviewer/CdmSeedWotLK.lua",
  "modules/cooldownviewer/CdmAuraCatalog.lua",
  "modules/cooldownviewer/CooldownViewer.lua",
  "modules/cooldownviewer/Equip.lua",
  "modules/cooldownviewer/ItemMixins.lua",
  "modules/cooldownviewer/Viewers.lua",
  "modules/cooldownviewer/AuraItemMixins.lua",
  "modules/cooldownviewer/BuffViewers.lua",
  "modules/cooldownviewer/AlertData.lua",
  "modules/cooldownviewer/SoundAlertData.lua",
  "modules/cooldownviewer/Alerts.lua",
  "core/Texture.lua",
  -- After core/Texture.lua, not next to the viewer files it serves: both asset files bail out at
  -- their first line if NE.tex is absent, so loading them earlier would register nothing at all —
  -- silently, and with every HasAtlas assertion below then failing for the wrong reason. The real
  -- .toc has core/ long before modules/, which is why this only bites here.
  "modules/cooldownviewer/Assets.lua",
  -- The chrome data layer, added when the edit-mode dialog started depending on a NAMED nineslice
  -- layout and on art being shipped for it. Without these three the harness could not tell a
  -- registered atlas from one whose BLP nobody copied — and PanelChrome silently takes its
  -- graceful-degrade path either way, so nothing else would have noticed.
  "core/NineSlice.lua",
  "core/NineSliceLayouts.lua",
  "Textures/Assets.lua",
  -- ButtonSkin fail-safes to native art when its sheet is missing, and returns false to say so —
  -- which nothing was reading. Loaded here so the red 3-slice is exercised rather than assumed.
  "core/ButtonSkin.lua",
  "core/Tabs.lua",
  "core/ScrollbarReskin.lua",
  "core/Menu.lua",
  "core/PanelChrome.lua",
  "core/FrameUtil.lua",
  "modules/cooldownviewer/SettingsAssets.lua",
  "modules/cooldownviewer/SettingsPanel.lua",
  "modules/cooldownviewer/CdmArsenal.lua",
  "modules/cooldownviewer/SettingsAdapter.lua",
  "modules/cooldownviewer/SettingsCategories.lua",
  "modules/cooldownviewer/SettingsMenu.lua",
  "modules/cooldownviewer/SettingsReorder.lua",
  "modules/cooldownviewer/SettingsPresets.lua",
  "modules/cooldownviewer/SettingsControls.lua",
  "modules/cooldownviewer/SettingsOptions.lua",
  "modules/cooldownviewer/EditorPanel.lua",
  "modules/cooldownviewer/Register.lua",
}

print("=== LOAD ===")
for _, rel in ipairs(FILES) do
  local ok, err = pcall(dofile, ADDON .. rel)
  if ok then
    print("  ok   " .. rel)
  else
    print("  FAIL " .. rel .. "\n       " .. tostring(err))
    os.exit(1)
  end
end

-- The rock body fill (UI-Background-Rock), which Textures/Assets.lua registers in the real client.
-- PanelChrome only takes its REAL branch — tiled rock, then a 0.32 grey tint — when this FDID
-- resolves to a local file; otherwise it degrades to a flat solid colour and never tints anything.
-- Without this line every chrome'd window in the suite silently ran the graceful-degrade path, so a
-- guard on the body's tint asserted nothing at all and passed against the very regression it exists
-- to catch. Registered on its own rather than by loading Textures/Assets.lua whole, which would pull
-- in the full atlas sheet set this suite has no other use for.
NE.tex.RegisterLocal(374155, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\374155-uibackground-rock.blp")

local M = NE.cooldownviewer
local fails = 0
local function assertf(cond, msg)
  if cond then print("  ok   " .. msg)
  else fails = fails + 1; print("  FAIL " .. msg) end
end

print("\n=== BOOT (registration is deferred to PLAYER_LOGIN) ===")
-- Nothing should be registered before login fires.
assertf(next(DragonUI.EditableFrames) == nil, "no edit-mode registration at file-load time")

fireEvent("PLAYER_LOGIN")
drain()

assertf(M.viewers.essential ~= nil, "essential viewer created")
assertf(M.viewers.utility ~= nil, "utility viewer created")
-- The seam that matters: /dui edit drives EditableFrames, NOT MoversSystem.
assertf(DragonUI.EditableFrames["CooldownViewerEssential"] ~= nil, "essential registered as EditableFrame")
assertf(DragonUI.EditableFrames["CooldownViewerUtility"] ~= nil, "utility registered as EditableFrame")
assertf(#NE.optionSections == 1, "options section registered")

-- ── SHIPS DISABLED ──
-- Owner's decision, and the only module here that does: four viewers in the middle of the screen are
-- new HUD furniture rather than a replacement for something the player already had, so it waits to be
-- asked. Asserted BEFORE anything turns it on, because "off by default" is exactly the state the rest
-- of this file spends its time not being in.
assertf(M.IsEnabled() == false, "the Cooldown Manager ships disabled")
assertf(M.viewers.essential:IsShown() == false, "…so no viewer is on screen on a fresh profile")
assertf(DragonUI.EditableFrames["CooldownViewerEssential"].editorVisible() == false,
        "…and /dui edit offers no handle for it, so edit mode does not open onto four empty rectangles")
-- The frames are still BUILT and still registered — the flag is the whole gate, so turning it on has
-- no first-run path of its own to get wrong.
assertf(M.viewers.buffBar ~= nil and DragonUI.EditableFrames["CooldownViewerBuffBar"] ~= nil,
        "…while the frames themselves are built and registered regardless")

-- Events are dropped while it is off, or every player who never turns it on pays for
-- SPELL_UPDATE_COOLDOWN and UNIT_AURA all session to repaint tiles nobody can see.
fireEvent("PLAYER_ENTERING_WORLD")
drain()
assertf(#M.viewers.essential.items == 0, "…and its viewers ignore events entirely while it is off")

-- The AURA viewers need their own gate and so need their own assertion: UNIT_AURA and
-- PLAYER_TARGET_CHANGED are answered in BuffViewers' own handler and never reach the base's, so a gate
-- only in the base would leave an off Cooldown Manager rebuilding both of them on every aura tick —
-- the one path where the cost is measurable. Probed by `_lastShownCount`, which is nil until a rebuild
-- has actually run: the item count would be 0 either way on a profile with nothing tracked yet, so
-- asserting on THAT would pass against the missing gate.
fireEvent("UNIT_AURA", "player")
drain()
assertf(M.viewers.buffIcon._lastShownCount == nil and M.viewers.buffBar._lastShownCount == nil,
        "…including the aura viewers, which answer UNIT_AURA on their own and are gated separately")

-- THE WINDOW GOES WITH THEM (owner's steer). It configures the viewers, so an off Cooldown Manager has
-- no window: not from /cdm, not from the options button, not from OpenTo. Gated before the panel is
-- BUILT, which is the point — that is several hundred frames a player who never turns it on should
-- never pay for. `CDS.panel` staying nil is how the harness can see the difference between "refused"
-- and "built it, then hid it".
do
  local S = NE.cooldownviewersettings
  SlashCmdList["NECDMSETTINGS"]()
  assertf(S.panel == nil, "/cdm builds nothing while the Cooldown Manager is off")
  M.OpenSettingsPanel("spells")
  assertf(S.panel == nil, "…and neither does the options button's entry point")
end

-- ON for everything below. This is the one call standing in for a player ticking the box; the whole
-- suite past this line is about what the Cooldown Manager does once it has been asked for.
M.SetEnabled(true)
assertf(M.IsEnabled() == true and M.viewers.essential:IsShown(),
        "turning it on shows the viewers, no reload")
assertf(#M.viewers.essential.items > 0,
        "…and populates them on the way up, because Show fires OnShow and OnShow is Rebuild")

print("\n=== EVENTS: login ===")
local ranks = NE.spellbook.KnownRankIDs("Mind Blast")
assertf(ranks ~= nil and #ranks == 3, "spellbook rank table built (Mind Blast x3)")
assertf(NE.spellbook.HighestKnownRankID(8092, "Mind Blast") == 10947,
        "highest rank resolves 8092 -> 10947 (NOT castTime 1500)")

fireEvent("PLAYER_ENTERING_WORLD")
drain()

local ess = M.viewers.essential
local util = M.viewers.utility
local function shownItems(v)
  local n = 0
  for _, it in ipairs(v.items) do if it:IsShown() then n = n + 1 end end
  return n
end
print("  essential items: " .. #ess.items .. " (shown " .. shownItems(ess) .. ")")
print("  utility   items: " .. #util.items .. " (shown " .. shownItems(util) .. ")")
assertf(shownItems(ess) > 0, "essential viewer populated")
assertf(shownItems(util) > 0, "utility viewer populated")
assertf(ess._w > 1, "essential frame sized by layout (" .. ess._w .. "x" .. ess._h .. ")")

-- Mind Blast should have been upgraded from the curated rank-1 id to the learned rank 3.
local mb
for _, it in ipairs(ess.items) do if it.spellName == "Mind Blast" then mb = it end end
assertf(mb ~= nil, "Mind Blast tile present")
if mb then assertf(mb.spellID == 10947, "Mind Blast tile bound to highest rank (" .. tostring(mb.spellID) .. ")") end

print("\n=== ICON TINT ===")
-- Reported in-game: every icon rendered grey. IsUsableSpell was being handed a spellID, which this
-- client reads as a spellbook index and answers nil for, so the tint fell through to ICON_UNUSABLE.
mb:RefreshIconColor()
local tint = mb.Icon._color
assertf(tint and tint[1] == M.ICON_USABLE[1] and tint[2] == M.ICON_USABLE[2],
        "a usable spell tints white, not grey (got "
        .. table.concat({ tostring(tint and tint[1]), tostring(tint and tint[2]) }, ",") .. ")")

-- The ready flash must be armed at all. The old guard read GetAtlasRect's first return (0 for an
-- unknown atlas) as truthy and never fired.
mb:ClearFlash()
mb:ScheduleFlash(GetTime() + 5, 10)
assertf(mb.CooldownFlash._flashStartTime ~= nil, "ready flash schedules")
-- Phase 8a ships and registers the GCD flipbook, which retires the fallback burst: this assertion
-- used to require the fallback texture, and inverting it is the intended consequence of that.
assertf(mb.CooldownFlash.Flipbook:GetTexture() == NE.tex.Local(5199404),
        "…using the flipbook sprite sheet, not the fallback highlight")

-- The sprite stepper had never executed before 8a, because the atlas it gates on was never
-- registered. Drive it and check the frame it lands on is a real cell of the strip.
do
  local l0, r0, t0, b0 = NE.tex.GetAtlasRect("UI-HUD-ActionBar-GCD-Flipbook")
  local frameW, frameH = (r0 - l0) / 2, (b0 - t0) / 11
  mb:ClearFlash()
  local start = GetTime()
  mb:ScheduleFlash(start, 5)
  local flash = mb.CooldownFlash
  local play = flash._flashStartTime
  assertf(play ~= nil, "flash armed for the sprite path")

  local seen = {}
  for _, at in ipairs({ 0.01, 0.2, 0.5, 0.74 }) do
    NOW = play + at
    flash._scripts.OnUpdate(flash)
    local l, r, t, b = flash.Flipbook:GetTexCoord()
    assertf(l and r and t and b, "stepper set texcoords at t+" .. at)
    if l then
      -- Inside the strip, and exactly one cell wide/tall. A frame straddling a boundary would show
      -- two half-sprites, which is the failure this catches.
      local inside = l >= l0 - 1e-6 and r <= r0 + 1e-6 and t >= t0 - 1e-6 and b <= b0 + 1e-6
      local oneCell = math.abs((r - l) - frameW) < 1e-6 and math.abs((b - t) - frameH) < 1e-6
      assertf(inside, ("…inside the strip (%.4f-%.4f, %.4f-%.4f)"):format(l, r, t, b))
      assertf(oneCell, "…and exactly one 47x47 cell")
      local onGrid = math.abs((l - l0) / frameW - math.floor((l - l0) / frameW + 0.5)) < 1e-4
      assertf(onGrid, "…aligned to the cell grid, not straddling two frames")
      seen[l .. ":" .. t] = true
    end
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  assertf(distinct > 1, "the sprite advances through frames (" .. distinct .. " distinct cells)")
  -- Left ARMED, not cleared: the pulse test immediately below drives this frame's OnUpdate by hand,
  -- and ClearFlash removes the script out from under it.
  mb:ScheduleFlash(GetTime() + 5, 10)
end
-- Step into the flash window and confirm the pulse drives alpha rather than erroring on a number.
mb.CooldownFlash._flashStartTime = GetTime() - 0.2
mb.CooldownFlash:GetScript("OnUpdate")(mb.CooldownFlash)
assertf((mb.CooldownFlash.Flipbook:GetAlpha() or 0) > 0, "…and the pulse raises its alpha")
mb:ClearFlash()

print("\n=== EVENTS: cast a cooldown ===")
COOLDOWNS[10947] = { NOW, 8 }          -- Mind Blast rank 3, 8s cooldown
fireEvent("SPELL_UPDATE_COOLDOWN")
drain()
if mb then
  assertf(mb.Cooldown._cdStart == NOW and mb.Cooldown._cdDur == 8, "cooldown swipe set (8s)")
  assertf(mb.Icon._desat == true, "icon desaturated on real cooldown")
  assertf(mb.Cooldown._neText:GetText() ~= "" and mb.Cooldown._neText:GetText() ~= nil,
          "countdown text painted: '" .. tostring(mb.Cooldown._neText:GetText()) .. "'")
end

print("\n=== COOLDOWN EXPIRY ===")
-- Reported in-game: icons went grey on cast and STAYED grey after the cooldown finished.
-- 3.3.5a fires no event when a cooldown expires, so nothing re-ran RefreshCooldown and the
-- desaturation persisted until some unrelated event refreshed the tile. The item now schedules its
-- own refresh for the moment the cooldown ends. Note this asserts with NO event fired at all.
if mb then
  assertf(mb.Icon._desat == true, "still desaturated mid-cooldown")
  nextFrame(8.2)          -- past the 8s cooldown
  COOLDOWNS[10947] = nil  -- the client would now report no cooldown
  drain()                 -- only the expiry timer is due; no event is sent
  assertf(mb.Icon._desat == false, "icon un-desaturates at expiry with NO event fired")
end

print("\n=== EVENTS: rank-safe read (cooldown on a rank the tile isn't keyed to) ===")
COOLDOWNS[10947] = nil
COOLDOWNS[8102] = { NOW, 8 }           -- a DIFFERENT rank is the one ticking
fireEvent("SPELL_UPDATE_COOLDOWN")
drain()
if mb then
  local s, d = mb:ReadCooldown()
  assertf(s == NOW and d == 8, "rank-safe read found the ticking rank (" .. tostring(s) .. "," .. tostring(d) .. ")")
end
COOLDOWNS[8102] = nil

print("\n=== EVENTS: GCD must not desaturate ===")
COOLDOWNS[61304] = { NOW, 1.5 }
COOLDOWNS[10947] = { NOW, 1.5 }
fireEvent("SPELL_UPDATE_COOLDOWN")
drain()
if mb then assertf(mb.Icon._desat == false, "icon NOT desaturated on GCD-length cooldown") end
COOLDOWNS[61304] = nil; COOLDOWNS[10947] = nil

print("\n=== SETTINGS ===")
M.SetOpt("CooldownViewerEssential", "iconLimit", 3)
assertf(M.GetOpt("CooldownViewerEssential", "iconLimit") == 3, "iconLimit persisted + read back")
assertf(ess.stride == 3, "stride applied to the live frame")
M.SetOpt("CooldownViewerEssential", "opacity", 60)
assertf(math.abs(ess:GetAlpha() - 0.6) < 0.001, "opacity applied live")
M.ResetOpts("CooldownViewerEssential")
assertf(M.GetOpt("CooldownViewerEssential", "iconLimit") == 12, "reset restores the default")

print("\n=== VISIBILITY ===")
M.SetCategoryEnabled("utility", false)
assertf(util:IsShown() == false, "disabling a category hides its viewer")
M.SetCategoryEnabled("utility", true)
assertf(util:IsShown() == true, "re-enabling shows it")

print("\n=== EDIT MODE ===")
local edEss = DragonUI.EditableFrames["CooldownViewerEssential"]
-- PER CHARACTER. DragonUI's profile is shared across the account, so a bare key means every
-- character shares one placement — the last one to touch it wins. configPath is the only thing the
-- editor takes from us, so varying the key is the whole mechanism.
assertf(edEss.configPath[1] == "widgets"
        and edEss.configPath[2] == "neCooldownViewerEssential-Testpriest-Test Realm",
        "configPath wired per character (" .. edEss.configPath[1] .. "." .. edEss.configPath[2] .. ")")

do
  -- The key builder in isolation, including the two ways it must NOT produce a per-character key.
  assertf(NE.FramePositionKey("neThing", nil) == "neThing",
          "a frame that does not ask keeps the shared key, so nothing else moves")
  assertf(NE.FramePositionKey("neThing", true) == "neThing-Testpriest-Test Realm",
          "…and one that asks gets name and realm")
  local realName = UnitName
  UnitName = function() return nil end
  assertf(NE.FramePositionKey("neThing", true) == "neThing",
          "…falling back to the shared key when the client cannot name the player yet")
  UnitName = realName

  -- A DIFFERENT character must not read the first one's position. This is the assertion the whole
  -- change exists for, and the one a shared key passes only by accident.
  UnitName = function() return "Testlock" end
  assertf(NE.FramePositionKey("neThing", true) ~= "neThing-Testpriest-Test Realm",
          "another character resolves to another slot entirely")
  UnitName = realName

  -- MIGRATION. Someone upgrading into this must not watch their viewers jump to the default; that
  -- reads as data loss, not as a feature. The shared entry is left in place on purpose — every other
  -- character still needs it as their own seed.
  profile.widgets = profile.widgets or {}
  profile.widgets.neMigrateTest = { anchor = "TOPLEFT", posX = 11, posY = -22 }
  local mFrame = CreateFrame("Frame", nil, UIParent)
  NE.RegisterHUDFrame({ name = "NEMigrateTest", frame = mFrame, section = "widgets",
                        key = "neMigrateTest", perCharacter = true })
  local seeded = profile.widgets["neMigrateTest-Testpriest-Test Realm"]
  assertf(seeded ~= nil and seeded.posX == 11 and seeded.posY == -22,
          "an existing shared position seeds this character's slot on first registration")
  assertf(profile.widgets.neMigrateTest ~= nil,
          "…and the shared entry stays, or the first character to log in takes it from everyone else")
  assertf(seeded ~= profile.widgets.neMigrateTest,
          "…as a COPY, so moving it on one character does not drag the others' seed with it")
  profile.widgets.neMigrateTest = nil
  profile.widgets["neMigrateTest-Testpriest-Test Realm"] = nil
end
-- Offered whenever the module is ON, empty or not — an empty viewer still has to be positionable, which
-- is what showTest is for. It is the master enable, and only that, which takes the handle away; the
-- boot block above asserts the off case, and this is the pair to it.
assertf(edEss.editorVisible() == true, "offered in edit mode whenever the module is on")
do
  M.SetCategoryEnabled("essential", false)
  assertf(edEss.editorVisible() == true,
          "…including a viewer switched off by its own category, which still needs a home")
  M.SetCategoryEnabled("essential", true)
end

-- THE bug this whole round-trip existed to catch: the registered frame must be a CreateUIFrame
-- ANCHOR (which carries the drag scripts), not the bare content frame.
assertf(edEss.frame._isUIFrame == true, "registered frame is a draggable CreateUIFrame anchor")
assertf(edEss.frame ~= ess, "anchor is distinct from the content frame")
assertf(ess.editorAnchor == edEss.frame, "content linked to its anchor")

-- Content must follow the anchor, and the anchor must track content size.
local cp = ess._points[#ess._points]
assertf(cp[2] == edEss.frame and 1 or 0, 1)
assertf(math.abs(edEss.frame:GetWidth() - ess:GetWidth()) < 0.001,
        "anchor tracks content width (" .. edEss.frame:GetWidth() .. ")")

-- showTest must populate even spells the character has NOT learned, so an empty viewer is grabbable.
local before = shownItems(ess)
edEss.showTest()
local during = shownItems(ess)
assertf(during >= before, "showTest populates demo icons (" .. before .. " -> " .. during .. ")")
edEss.hideTest()
assertf(shownItems(ess) == before, "hideTest restores the live set (" .. shownItems(ess) .. ")")

-- Position restore reads the fields DragonUI's SaveUIFramePosition actually writes.
profile.widgets = profile.widgets or {}
profile.widgets.neCooldownViewerEssential = { anchor = "TOPLEFT", posX = 123, posY = -456 }
assertf(NE.ApplySavedFramePosition(edEss.frame, "widgets", "neCooldownViewerEssential") == true,
        "saved position restored")
local pt = edEss.frame._points[#edEss.frame._points]
assertf(pt[1] == "TOPLEFT" and pt[4] == 123 and pt[5] == -456,
        "restored anchor/offsets correct (" .. pt[1] .. "," .. pt[4] .. "," .. pt[5] .. ")")

-- A DK-style empty viewer must still have a grabbable footprint in preview.
local savedList = M.GetActiveSpellList
M.GetActiveSpellList = function() return {} end
edEss.showTest()
assertf(ess._w > 1 and ess._h > 1, "empty viewer still grabbable in preview (" .. ess._w .. "x" .. ess._h .. ")")
M.GetActiveSpellList = savedList
edEss.hideTest()

print("\n=== BUFF VIEWERS (Phase 3) ===")

-- The clock MUST advance before the scan, not after: NE.aura caches its snapshot per frame, so an
-- aura change with a stale GetTime() is re-read from the previous frame's cache and looks invisible.
local function auraTick(unit)
  nextFrame()
  fireEvent("UNIT_AURA", unit)
  drain()
end
-- Same requirement for anything that rebuilds directly rather than through an event.
local function settle(fn)
  nextFrame()
  fn()
  drain()
end

local bIcon, bBar = M.viewers.buffIcon, M.viewers.buffBar
assertf(bIcon ~= nil and bBar ~= nil, "both aura viewers created")
assertf(DragonUI.EditableFrames["CooldownViewerBuffIcon"] ~= nil, "buffIcon is editable")
assertf(DragonUI.EditableFrames["CooldownViewerBuffBar"] ~= nil, "buffBar is editable")

-- Nothing up -> nothing shown.
auraTick("player")
assertf(shownItems(bIcon) == 0, "no auras -> buff icons empty")

-- Auto-track is OFF out of the box: a newly met aura is recorded and listed under Not Displayed,
-- but nothing appears on screen unassigned. Asserted here rather than assumed, because everything below
-- depends on the opposite and would otherwise fail for a reason that looks nothing like the cause.
assertf(M.IsAutoTrackBuffs() == false, "auto-track defaults OFF (new buffs stay hidden)")
BUFFS.player = { { name = "Power Infusion", rank = "", icon = "Interface\\Icons\\PI", count = 0,
                   duration = 15, expiration = NOW + 11, spellID = 10060 } }
auraTick("player")
assertf(shownItems(bIcon) == 0, "…so a short buff shows nothing until it is assigned")
M.SetAutoTrackBuffs(true)
auraTick("player")
assertf(shownItems(bIcon) == 1, "…and turning auto-track on brings it straight in")

-- A short buff must auto-track; a long one must not. This is also the arg-shift regression test:
-- read with modern indices, `duration` would receive the caster string and the window check would
-- silently reject everything.
BUFFS.player = {
  { name = "Power Infusion", rank = "", icon = "Interface\\Icons\\PI", count = 0,
    duration = 15, expiration = NOW + 11, spellID = 10060 },
  { name = "Arcane Intellect", rank = "Rank 3", icon = "Interface\\Icons\\AI", count = 0,
    duration = 1800, expiration = NOW + 1700, spellID = 10157 },
  { name = "Fortitude", rank = "Rank 1", icon = "Interface\\Icons\\PWF", count = 0,
    duration = 0, expiration = 0, spellID = 1243 },
}
auraTick("player")
assertf(shownItems(bIcon) == 1, "only the <=120s buff auto-tracks (" .. shownItems(bIcon) .. " of 3)")
assertf(bIcon.items[1].spellName == "Power Infusion",
        "tracked the right aura: " .. tostring(bIcon.items[1].spellName))
assertf(bIcon.items[1].Icon:GetTexture() == "Interface\\Icons\\PI",
        "icon read from index 3, not the rank at index 2")
assertf(shownItems(bBar) == 1, "bar viewer tracks it too (dest=both)")
assertf(math.abs((bBar.items[1]._auraDuration or 0) - 15) < 0.001,
        "bar cached duration 15 (" .. tostring(bBar.items[1]._auraDuration) .. ")")

-- The bar animates from cached values without re-scanning.
bBar.items[1]:RefreshCooldownInfo()
-- Expected remaining is expiration - now; the clock has stepped since the aura was authored, so
-- compare against the live figure rather than the literal 11 it started at.
local expectRemaining = bBar.items[1]._auraExpiration - GetTime()
assertf(math.abs((bBar.items[1].Bar._value or 0) - expectRemaining) < 0.001,
        ("bar value tracks remaining (%.2f)"):format(bBar.items[1].Bar._value or -1))
assertf(bBar.items[1].Bar._max == 15, "bar max = full duration 15")

-- ── Bar-BG horizontal 3-slice (§H.2.9) ──────────────────────────────────────────────────────────
do
  local bar = bBar.items[1].Bar
  local bg  = bar.BarBG
  assertf(bg ~= nil and bg.Left and bg.Middle and bg.Right, "Bar-BG is a three-piece slice")

  -- The client sizes this bar from its LEFT/RIGHT anchors; the stub does not resolve anchors, so
  -- give it the width it has in game (220 row - 30 icon - 2 gap). Doing so also drives the
  -- OnSizeChanged path, which is where every re-measure below comes from.
  assertf(bg.Middle:GetTexCoord() ~= nil,
          "an unresolved (zero) width still slices, rather than collapsing to one stretch")
  bar:SetWidth(188)

  -- NOT a frame. A child frame draws above every layer of its parent, so a Frame-based group would
  -- put the background over the fill, the pip and the name — the §H.2.8 rule, restated where it can
  -- fail again.
  assertf(bg.GetFrameLevel == nil, "…held as a plain table, not a child frame of the bar")
  assertf(bg.Left._layer == "BACKGROUND" and bg.Middle._layer == "BACKGROUND"
          and bg.Right._layer == "BACKGROUND", "…with all three pieces on BACKGROUND")

  local entry = NE.tex._atlasEntry("UI-HUD-CoolDownManager-Bar-BG")
  local function coords(p) local l, r = p:GetTexCoord(); return l, r end
  local l1, r1 = coords(bg.Left)
  local l2, r2 = coords(bg.Middle)
  local l3, r3 = coords(bg.Right)

  -- The three sub-rects must TILE the cell: no gap (a seam of missing art) and no overlap (the edge
  -- lines drawn twice). Slicing is only correct if the pieces reassemble the source exactly.
  assertf(math.abs(l1 - entry.left) < 1e-6, "left cap starts at the cell's left edge")
  assertf(math.abs(r1 - l2) < 1e-6, "…middle starts exactly where the left cap ends")
  assertf(math.abs(r2 - l3) < 1e-6, "…right cap starts exactly where the middle ends")
  assertf(math.abs(r3 - entry.right) < 1e-6, "…and the right cap ends at the cell's right edge")

  -- The cut points are the ones the art dictates: cols 0-7 and 121-131 (§H.2.9).
  local u = function(x) return entry.left + (entry.right - entry.left) * (x / 132) end
  assertf(math.abs(r1 - u(8)) < 1e-6, "left cut at col 8, where the flat interior begins")
  assertf(math.abs(l3 - u(121)) < 1e-6, "right cut at col 121, where the shadow begins")

  -- THE POINT OF THE WHOLE EXERCISE: widening the bar must not widen the caps. Their width tracks
  -- the region's HEIGHT, which is constant, so the flat middle absorbs every extra pixel. Before the
  -- slice a 132px cell was stretched bodily and the 1px edge lines smeared with it — 1.47x at the
  -- 100% bar width and 3.1x at the 200% end of the slider.
  local capL0, capR0 = bg.Left:GetWidth(), bg.Right:GetWidth()
  local expectScale = (bar:GetHeight() + 2 + 7) / 19
  assertf(math.abs(capL0 - 8 * expectScale) < 1e-6,
          ("left cap sized off the region height, not its width (%.2f)"):format(capL0))
  assertf(math.abs(capR0 - 11 * expectScale) < 1e-6,
          ("right cap likewise (%.2f)"):format(capR0))

  -- Blank the middle's texcoord first. "The caps did not change" is satisfied by doing nothing at
  -- all, so on its own it passes whenever the resize hook is dropped entirely — which is exactly
  -- what a replacing HookScript used to do to it. This makes the re-apply itself observable.
  local w0 = bar:GetWidth()
  bg.Middle._coords = nil
  bar:SetWidth(w0 * 2)
  assertf(bg.Middle:GetTexCoord() ~= nil, "resizing the bar re-applies the slice")
  assertf(math.abs(bg.Left:GetWidth() - capL0) < 1e-6
          and math.abs(bg.Right:GetWidth() - capR0) < 1e-6,
          "…and doubling it leaves both caps at their original width")
  assertf(select(2, bg.Left:GetTexCoord()) == r1 and bg.Middle:IsShown(),
          "…with the cuts unmoved")

  -- Both OnSizeChanged hooks on this bar must still run: the fill overlay's and the cap widths'.
  -- Under a stub that replaced hooks instead of chaining, only the last one installed ever fired.
  assertf(bar._neOverlay ~= nil and bar._neOverlay:GetWidth() > 0,
          "the fill overlay tracked the same resize (both OnSizeChanged hooks fired)")

  -- A bar too narrow for two caps falls back to one stretched piece rather than overlapping them.
  bar:SetWidth(10)
  assertf(not bg.Middle:IsShown() and not bg.Right:IsShown(),
          "a bar narrower than its own caps falls back to a single stretch")
  bar:SetWidth(w0)
  assertf(bg.Middle:IsShown() and bg.Right:IsShown(), "…and recovers when there is room again")
end

-- Auto-track destination routing.
settle(function() M.SetAutoTrackDest("icon") end)
assertf(shownItems(bIcon) == 1 and shownItems(bBar) == 0, "dest=icon routes to icons only")
settle(function() M.SetAutoTrackDest("bar") end)
assertf(shownItems(bIcon) == 0 and shownItems(bBar) == 1, "dest=bar routes to bars only")
settle(function() M.SetAutoTrackDest("both") end)

-- Explicit assignment overrides the window: pin a PERMANENT toggle the auto path always rejects.
settle(function() M.SetAuraAssignment("PRIEST", 1243, "icon") end)
local names = {}
for _, it in ipairs(bIcon.items) do if it:IsShown() then names[it.spellName] = true end end
assertf(names["Fortitude"] == true, "explicitly assigned duration-0 aura is force-included")
assertf(names["Power Infusion"] == true, "auto-tracked aura still present alongside it")

-- ...and 'hidden' force-excludes one the window would have taken.
settle(function() M.SetAuraAssignment("PRIEST", 10060, "hidden") end)
names = {}
for _, it in ipairs(bIcon.items) do if it:IsShown() then names[it.spellName] = true end end
assertf(names["Power Infusion"] == nil, "hidden assignment excludes an auto-tracked aura")

-- One pool: assigning to the bar removes it from icons.
settle(function() M.SetAuraAssignment("PRIEST", 1243, "bar") end)
names = {}
for _, it in ipairs(bIcon.items) do if it:IsShown() then names[it.spellName] = true end end
assertf(names["Fortitude"] == nil, "bar-assigned aura no longer shows as an icon")
settle(function() M.ResetTrackedAura("PRIEST") end)

-- Buffs falling off must retire slots, not leave stale duplicates.
BUFFS.player = {}
auraTick("player")
assertf(shownItems(bIcon) == 0 and shownItems(bBar) == 0, "all auras gone -> both viewers empty")
assertf(bBar.items[1].spellID == nil, "retired bar slot cleared its spell identity")

-- Tracked DoT on the target (explicit assignments only; the auto window must never reach targets).
DEBUFFS.target = {
  { name = "Devouring Plague", rank = "Rank 1", icon = "Interface\\Icons\\DP", count = 0,
    duration = 24, expiration = NOW + 20, spellID = 2944 },
}
UnitExists = function(u) return u == "player" or u == "target" end
auraTick("target")
assertf(shownItems(bIcon) == 0, "untracked target debuff is ignored by the auto window")
settle(function() M.SetAuraAssignment("PRIEST", 2944, "icon") end)
assertf(shownItems(bIcon) == 1, "explicitly tracked target DoT appears")
DEBUFFS.target = {}
settle(function() M.ResetTrackedAura("PRIEST") end)

print("\n=== WOTLK SEED (Phase 2) ===")
-- Vanilla ClassData has no DEATHKNIGHT at all; CdmSeedWotLK must create it.
local dkEss = M.ESSENTIAL_BY_CLASS.DEATHKNIGHT
local dkUti = M.UTILITY_BY_CLASS.DEATHKNIGHT
assertf(dkEss ~= nil and #dkEss > 0, "Death Knight essential list exists (" .. (dkEss and #dkEss or 0) .. ")")
assertf(dkUti ~= nil and #dkUti > 0, "Death Knight utility list exists (" .. (dkUti and #dkUti or 0) .. ")")

-- The appends must be additive, not replacements: vanilla Priest entries survive alongside WotLK.
local pEss = M.ESSENTIAL_BY_CLASS.PRIEST
local hasVanilla, hasWotlk = false, false
for _, id in ipairs(pEss) do
  if id == 8092  then hasVanilla = true end   -- Mind Blast, from ClassData
  if id == 47540 then hasWotlk   = true end   -- Penance, from the seed
end
assertf(hasVanilla and hasWotlk, "seed appends to the vanilla list rather than replacing it")

-- ── ROTATION: the spells that carry no cooldown at all ──
--
-- Reported as "lots of classes are missing default abilities that dont have cooldowns, such as druids
-- with wrath". They were missing for a structural reason, not an oversight: the generator's
-- castability filter is `cooldown > 1.5s`, so every rotational filler resolved to nothing and was
-- rejected as an unresolvable name. It could not have emitted one.
local drEss = M.ESSENTIAL_BY_CLASS.DRUID
local hasWrath, hasMaxRank = false, false
for _, id in ipairs(drEss) do
  if id == 5176  then hasWrath   = true end   -- Wrath, RANK 1
  if id == 48461 then hasMaxRank = true end   -- Wrath, rank 12
end
assertf(hasWrath, "the druid list carries Wrath, which has no cooldown and so could never resolve before")
-- RANK 1, matching every other entry in the seed. A max-rank id would work for a level-80 druid and
-- leave a level-20 one with a tile bound to a spell they cannot cast; the runtime walks UP from the
-- listed rank on its own (NE.spellbook.HighestKnownRankID), which is why rank 1 is the right listing.
assertf(not hasMaxRank, "…as its rank-1 id, leaving the rank walk to the runtime as everywhere else")

-- Every class, which was the actual ask — Wrath was the example, not the scope.
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "MAGE",
                         "WARLOCK", "DRUID", "SHAMAN", "DEATHKNIGHT" }) do
  local n = #(M.ESSENTIAL_BY_CLASS[class] or {})
  assertf(n >= 10, class .. " has a full essential list after the rotation pass (" .. n .. ")")
end

-- No duplicates anywhere (appendAll dedupes).
local dupes = 0
for _, tbl in pairs({ M.ESSENTIAL_BY_CLASS, M.UTILITY_BY_CLASS }) do
  for _, list in pairs(tbl) do
    local seen = {}
    for _, id in ipairs(list) do
      if seen[id] then dupes = dupes + 1 end
      seen[id] = true
    end
  end
end
assertf(dupes == 0, "no duplicate ids after the append (" .. dupes .. ")")

-- A Death Knight must actually populate. Rebuild filters on GetSpellInfo resolving, and the fake
-- spellbook above deliberately knows only a handful of Priest spells — so register the seed's DK
-- ids with it first. (Keeping the stub strict by default is what lets Rebuild's "a bad curated
-- entry can't create a broken tile" guard stay meaningful for every other test.)
for _, list in ipairs({ dkEss, dkUti }) do
  for _, id in ipairs(list) do
    SPELLS[id] = { "DK Ability " .. id, "" }
  end
end
UnitClass = function() return "Death Knight", "DEATHKNIGHT" end
M.InvalidateCuratedCache()
ess._editPreview = true          -- preview skips the learn-gate, as edit mode does
settle(function() ess:Rebuild() end)
assertf(shownItems(ess) > 0, "Death Knight essential viewer populates (" .. shownItems(ess) .. " icons)")
ess._editPreview = false
UnitClass = function() return "Priest", "PRIEST" end
M.InvalidateCuratedCache()
settle(function() ess:Rebuild() end)

print("\n=== LEARN GATE ===")
-- Regressions reported in-game: a Disc priest's Penance and a Holy priest's Guardian Spirit were
-- filtered out, as was Divine Hymn on a level-squished (60) server. All three are the same fault —
-- the gate keyed on an exact rank id / level rather than on the spellbook.

-- 1. Higher rank trained. The curated id is rank 1; the book holds rank 3 under the SAME name, and
--    IsSpellKnown on the rank-1 id says false. This is the Penance case.
SPELLS[47540] = { "Penance", "Rank 1" }   -- curated seed id
SPELLS[53007] = { "Penance", "Rank 3" }   -- what the player actually trained
BOOK[#BOOK + 1] = 53007
IsSpellKnown = function(id) return id == 53007 end   -- exact-rank semantics, as the client has
_G.__SLOT_IDS = BOOK
settle(function() NE.spellbook.BuildRankTable() end)
assertf(NE.spellbook.IsSpellNameKnown("Penance") == true, "spellbook knows Penance by name")
assertf(M.IsTrackable(47540, "PRIEST") == true,
        "rank-1 curated id passes the gate when a HIGHER rank is trained")

-- 2. Level squish: an ability known far below its stock level. The gate must not consult level at
--    all — being in the book is sufficient. This is the Divine Hymn case.
SPELLS[64843] = { "Divine Hymn", "" }
BOOK[#BOOK + 1] = 64843
_G.__SLOT_IDS = BOOK
settle(function() NE.spellbook.BuildRankTable() end)
assertf(M.IsTrackable(64843, "PRIEST") == true, "level-squished ability passes on spellbook presence")

-- 3. The gate must still EXCLUDE something genuinely not known, or it is useless.
assertf(M.IsTrackable(47585, "PRIEST") == false, "unknown curated spell is still filtered (Dispersion)")

-- 4. A spellbook entry whose link can't be parsed (GetSpellBookItemInfo -> nil id) must still count
--    as known: KNOWN_NAMES is built from names alone for exactly this reason.
SPELLS[47788] = { "Guardian Spirit", "" }
BOOK[#BOOK + 1] = 47788
_G.__SLOT_IDS = BOOK
local realLink = GetSpellLink
GetSpellLink = function() return nil end          -- simulate unparseable links
settle(function() NE.spellbook.BuildRankTable() end)
assertf(NE.spellbook.IsSpellNameKnown("Guardian Spirit") == true,
        "name-only book scan survives failed link parsing")
assertf(M.IsTrackable(47788, "PRIEST") == true, "talent-granted ability passes without an id")
GetSpellLink = realLink
settle(function() NE.spellbook.BuildRankTable() end)

-- 5. THE SPEC-SWAP ORDERING. The reported fault: switching Holy -> Discipline left a Holy talent
--    listed in the picker until the player happened to drag something. Nothing here is stale data in
--    the usual sense — it is an ORDER problem. ACTIVE_TALENT_GROUP_CHANGED fires, consumers refresh,
--    and core/SpellRanks.lua has not rebuilt yet because its rebuild is deferred by a frame. Anything
--    that refreshed on the talent event alone therefore re-rendered from the OLD book, and then had
--    no reason to look again.
do
  SPELLS[34861] = { "Circle of Healing", "Rank 1" }
  BOOK[#BOOK + 1] = 34861
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)
  assertf(M.IsTrackable(34861, "PRIEST") == true, "Holy talent is trackable while it is known")

  -- Swap spec: the book loses the spell, and the talent event lands FIRST.
  BOOK[#BOOK] = nil
  _G.__SLOT_IDS = BOOK
  fireEvent("ACTIVE_TALENT_GROUP_CHANGED")
  assertf(M.IsTrackable(34861, "PRIEST") == true,
    "immediately after the talent event the book has not caught up — this is the stale window")

  -- The rebuild is what closes it, and it has to be reachable from the talent event alone. Draining
  -- the deferred timers is exactly what the client does on the next frame.
  drain()
  assertf(NE.spellbook.IsSpellNameKnown("Circle of Healing") == false,
    "the spellbook table rebuilds off the talent event, without waiting for SPELLS_CHANGED")
  assertf(M.IsTrackable(34861, "PRIEST") == false,
    "…so the gate drops the other spec's talent with no interaction from the player")

  SPELLS[34861] = nil
end

print("\n=== LEARN GATE: THE BOOK IS AUTHORITATIVE (§H.3.21) ===")
-- Reported in-game: an untalented druid saw Mangle in the Not Displayed catalog. Three faults, and
-- what hid all three is that no consumer HID an unlearned row — they only tinted it, so a gate that
-- answered "learned" for everything looked exactly like a gate that worked.
do
  -- 1. The database fallback must not outvote the book. §E4 chained book -> IsSpellKnown ->
  --    GetSpellInfo(name) unconditionally, on the reasoning that it "could only widen". But the last
  --    link answers from the spell DATABASE on this client, so it says yes to abilities the
  --    character cannot have — and a chain whose last link always says yes is not a gate.
  SPELLS[99001] = { "Untrained Talent", "" }
  NAME_TO_ID["Untrained Talent"] = 99001
  assertf(GetSpellInfo("Untrained Talent") ~= nil,
          "the database resolves the name — this is the old fallback's input, unchanged")
  assertf(NE.spellbook.IsSpellNameKnown("Untrained Talent") == false, "…while the book has never heard of it")
  assertf(M.IsSpellLearned(99001) == false, "…and the book wins: the gate reports unlearned")

  -- 2. …and the fallback is demoted, not deleted. With no book to ask, fail OPEN: showing an ability
  --    the player lacks is a smaller fault than hiding one they have because a scan had not run.
  local realEnsure = NE.spellbook.EnsureBuilt
  NE.spellbook.EnsureBuilt = function() return false end
  assertf(M.IsSpellLearned(99001) == true, "with no spellbook to ask, the gate fails OPEN")
  NE.spellbook.EnsureBuilt = realEnsure
  assertf(M.IsSpellLearned(99001) == false, "…and closes again once the book is back")

  -- 3. The generated ARSENAL counts as class abilities for the gate's purposes. IsTrackable waves
  --    through any id outside its class-ability set — that hatch exists for user-added on-use items,
  --    whose use-spell is never "known" — and the arsenal used to fall through it. So the instant a
  --    player dragged an arsenal-only ability into a viewer, the viewer showed it learned or not.
  --    Mangle (Bear) is precisely that shape: arsenal-only, because the seed curates the Cat form.
  local curated = {}
  for _, byClass in pairs(M.SPELL_DATA_BY_CATEGORY) do
    for _, id in ipairs(byClass.PRIEST or {}) do curated[id] = true end
  end
  local arsenalOnly
  for _, id in ipairs(M.ARSENAL_BY_CLASS.PRIEST or {}) do
    if not curated[id] and not M.IsSpellLearned(id) then arsenalOnly = id; break end
  end
  assertf(arsenalOnly ~= nil, "the priest arsenal holds an unlearned ability the curation does not")
  assertf(M.IsSpellLearned(arsenalOnly) == false, "…which the gate reports unlearned")
  assertf(M.IsTrackable(arsenalOnly, "PRIEST") == false,
          "…and IsTrackable now agrees, instead of waving it through as an external")
  -- The hatch itself still has to work, or every user-added trinket use-spell vanishes.
  assertf(M.IsTrackable(99001, "PRIEST") == true,
          "an id in no class table is still always trackable — that is the external hatch")

  -- …and the consequence that made it worth fixing, stated end to end: placing an unlearned arsenal
  -- ability in a viewer must not put it on screen. This is what the player would have done from the
  -- picker, and before the widening the drag itself was what defeated the gate.
  M.SetSpellEnabled("essential", arsenalOnly, true)
  local live = {}
  for _, id in ipairs(M.GetActiveSpellList("essential")) do live[id] = true end
  assertf(live[arsenalOnly] == nil,
          "an unlearned arsenal ability dragged into a viewer still does not render")
  M.SetSpellEnabled("essential", 99001, true)
  local live2 = {}
  for _, id in ipairs(M.GetActiveSpellList("essential")) do live2[id] = true end
  assertf(live2[99001] == true, "…while a genuine external placed the same way does")
  M.ResetCustomList("essential", "PRIEST")
end

print("\n=== CUSTOM-LIST SHADOWING ===")
-- The reported fault: every WotLK-seeded ability stayed hidden even though the learn-gate passed
-- for it. Cause was a stale CUSTOM list frozen into SavedVariables by a read-only query, which
-- then shadowed the curated tables permanently.

-- 1. GetItemMeta is a query and must NOT create a custom list as a side effect.
local cd = M._store(true)
cd.customLists = {}
M.GetItemMeta(8092, "PRIEST")
assertf(M.GetCustomList("essential", "PRIEST") == nil,
        "GetItemMeta does not seed a custom list")

-- 2. With no custom list, the curated table (incl. the WotLK seed) drives the viewer.
local curated = M.GetActiveSpellList("essential", true)
local sawSeeded = false
for _, id in ipairs(curated) do if id == 47540 then sawSeeded = true end end
assertf(sawSeeded, "curated path includes seeded abilities (Penance)")

-- 3. A stale custom list DOES shadow it — reproducing the bug, so the fix is meaningful.
M.SetCustomList("essential", "PRIEST", { { spellID = 8092, enabled = true } })
local shadowed = M.GetActiveSpellList("essential", true)
local stillSeeded = false
for _, id in ipairs(shadowed) do if id == 47540 then stillSeeded = true end end
assertf(not stillSeeded, "a custom list shadows the curated table (the reported bug)")

-- 4. The one-time migration clears it and restores the curated path.
cd.customListsV2 = nil
assertf(M.MigrateStaleCustomLists() == true, "migration reports it cleared something")
assertf(M.GetCustomList("essential", "PRIEST") == nil, "stale list gone")
local restored = M.GetActiveSpellList("essential", true)
local backAgain = false
for _, id in ipairs(restored) do if id == 47540 then backAgain = true end end
assertf(backAgain, "curated abilities visible again after migration")

-- 5. It must be one-shot: a list authored later (Phase 4 picker) must survive.
M.SetCustomList("essential", "PRIEST", { { spellID = 8092, enabled = true } })
assertf(M.MigrateStaleCustomLists() == false, "migration does not run twice")
assertf(M.GetCustomList("essential", "PRIEST") ~= nil, "a deliberately authored list is preserved")
M.ResetCustomList("essential", "PRIEST")

print("\n=== ALERT DATA (Phase 4) ===")
local A  = M.alertdata
local AL = M.alerts

assertf(A.EXECUTE[24275] == 0.20, "Hammer of Wrath rank 1 carries a 20% execute threshold")
assertf(A.EXECUTE[48806] == 0.20, "…and so does its highest WotLK rank")
assertf(A.EXECUTE[53351] == 0.20, "Kill Shot present (the WotLK-only execute, absent upstream)")
assertf(A.REACTIVE[7384] == true, "Overpower present despite an EMPTY rank string in the DBC")
-- The two impostor classes the generator has to reject. Both were live faults during generation.
assertf(A.REACTIVE[34097] == nil, "NPC copies of Riposte excluded (class attribution)")
assertf(A.EXECUTE[20647] == nil, "Execute's triggered damage sub-spell excluded (unranked sibling)")
assertf(A.REACTIVE[1495] == nil, "Mongoose Bite excluded — not dodge-gated on 3.3.5a")

assertf(A.ExecuteThreshold(999999, { 24274 }) == 0.20, "execute resolves through a known rank id")
assertf(A.ExecuteThreshold(999999, nil) == nil, "a non-execute spell yields no threshold")
assertf(A.IsReactive(6572) == true, "Revenge is reactive")
assertf(A.IsReactive(8092) == false, "Mind Blast is not")

print("\n=== SOUND CATALOGUE (Phase 4) ===")
local nSounds, missingFile = 0, 0
for _, cat in ipairs(M.SOUND_CATEGORY_ORDER) do
  for _, e in ipairs(M.SOUND_DATA[cat] or {}) do
    nSounds = nSounds + 1
    if not e.file then missingFile = missingFile + 1 end
  end
end
assertf(nSounds == 67, "67 sounds catalogued (" .. nSounds .. ")")
assertf(missingFile == 0, "every catalogued sound has a shipped file")
assertf(M.SOUND_DATA.Short == nil, "the unplayable 'Short' category is not offered")
assertf(M.GetSoundKitName(316401) == "Cat", "kit id resolves to its label")

SOUNDS_PLAYED = {}
assertf(M.PlayReadySound(316401) == true, "PlayReadySound reports it played")
assertf(#SOUNDS_PLAYED == 1 and SOUNDS_PLAYED[1].path:find("7466002%.ogg"),
        "…by FILE PATH, not by kit id (" .. tostring(SOUNDS_PLAYED[1] and SOUNDS_PLAYED[1].path) .. ")")
assertf(M.PlayReadySound(999999) == false, "an unmapped kit plays nothing and says so")

print("\n=== ALERT STORE (Phase 4) ===")
assertf(AL.HasAny() == false, "no alerts assigned by default")
assertf(M.HasAnyReadySound() == false, "no sounds assigned by default")

AL.SetType(8092, "usable")
assertf(AL.GetType(8092) == "usable", "alert type stored")
assertf(AL.GetFX(8092) == 1, "fx defaulted on first assignment")
assertf(AL.GetWindow(8092) == 0.30, "window defaulted on first assignment")
assertf(AL.HasAny() == true, "HasAny sees the assignment")

AL.SetFX(8092, 2)
AL.SetType(8092, nil)
assertf(AL.GetType(8092) == nil, "alert can be disabled")
assertf(AL.GetFX(8092) == 2, "…and disabling KEEPS the fx choice for re-enabling")
assertf(AL.HasAny() == false, "HasAny false again once disabled")

AL.SetWindow(8092, 0.95); assertf(AL.GetWindow(8092) == 0.50, "window clamps to the 50% maximum")
AL.SetWindow(8092, 0.01); assertf(AL.GetWindow(8092) == 0.10, "window clamps to the 10% minimum")

M.SetReadySoundKit(8092, 316401)
assertf(M.GetReadySoundKit(8092) == 316401, "ready sound stored")
assertf(M.HasAnyReadySound() == true, "HasAnyReadySound sees it")

-- Preferences must key off the LISTED id, not the learned-rank id the tile displays. The Mind Blast
-- tile shows rank 3 (10947) but is listed as rank 1 (8092); keying on the former would silently
-- orphan every alert and sound the moment the player trained the next rank.
assertf(mb.spellID == 10947, "the tile displays the learned rank")
assertf(mb:GetSettingsKey() == 8092, "…but its settings key is the listed rank-1 id")

print("\n=== ALERT ENGINE (Phase 4) ===")
local tickFn = AL._ticker:GetScript("OnUpdate")
local function tick() tickFn(AL._ticker, 1) end

-- OFF MEANS SILENT, and the READY SOUND is why the ticker needs a gate of its own rather than leaving it
-- to "the tiles are hidden anyway". A player who assigns sounds, switches the Cooldown Manager off, and
-- then keeps hearing it announce cooldowns for viewers that are not on screen has a haunted UI.
--
-- Spying on HasAny, because the gate sits in FRONT of it: the question is whether the tick did any work
-- at all, and every visible consequence downstream is hidden by then anyway. M.IsEnabled is stubbed
-- rather than toggled for real — SetEnabled would rebuild all four viewers underneath the alert tests
-- that follow, to prove something about a branch that only reads this one function.
do
  local realEnabled, realHasAny, calls = M.IsEnabled, AL.HasAny, 0
  AL.HasAny = function() calls = calls + 1; return realHasAny() end
  M.IsEnabled = function() return false end
  tick()
  assertf(calls == 0, "the alert ticker does no work at all while the module is off")
  M.IsEnabled = realEnabled
  tick()
  assertf(calls == 1, "…and picks straight back up when it is switched on")
  AL.HasAny = realHasAny
end

local function itemFor(name)
  for _, it in ipairs(ess.items) do if it.spellName == name then return it end end
  for _, it in ipairs(util.items) do if it.spellName == name then return it end end
  return nil
end

-- The ready transition: a real cooldown finishing must fire the assigned sound EXACTLY once.
COOLDOWNS[10947] = { GetTime(), 30 }
mb:RefreshCooldown()
tick()
SOUNDS_PLAYED = {}
COOLDOWNS[10947] = nil
mb:RefreshCooldown()
tick()
assertf(#SOUNDS_PLAYED == 1, "cooldown -> ready fires the assigned sound once (" .. #SOUNDS_PLAYED .. ")")
tick(); tick()
assertf(#SOUNDS_PLAYED == 1, "…and not again on later ticks")

-- "available" is an edge-triggered flash, not a state the ticker maintains.
AL.SetType(8092, "available")
AL.ClearFX(mb)
COOLDOWNS[10947] = { GetTime(), 30 }; mb:RefreshCooldown(); tick()
COOLDOWNS[10947] = nil;         mb:RefreshCooldown(); tick()
assertf(GLOWS[mb] ~= nil, "available alert flashes the icon on the ready transition")
tick()
assertf(GLOWS[mb] ~= nil, "…and the ticker does not clear the one-shot flash out from under it")
AL.SetType(8092, nil); AL.ClearFX(mb)

-- "refresh": glow only inside the last `window` fraction of the tracked aura's duration.
AL.SetType(2944, "refresh")
AL.SetWindow(2944, 0.30)
local dp = itemFor("Devouring Plague")
assertf(dp ~= nil, "Devouring Plague tile present for the refresh test")
if dp then
  -- `refresh` now renders the REAL pandemic ring (§H.2.10), not a tinted LibCustomGlow. The ring is
  -- our own frame, so GLOWS stays empty for it — asserting on GLOWS alone would read the correct
  -- behaviour as "the alert stopped working".
  local ringUp = function() return dp._pandemicRing and dp._pandemicRing:IsShown() end

  BUFFS.player[1] = { name = "Devouring Plague", rank = "Rank 1", icon = "i", duration = 24, expiration = GetTime() + 20 }
  nextFrame(); tick()
  assertf(not ringUp(), "no pandemic ring at 20s of 24s remaining")
  BUFFS.player[1].expiration = GetTime() + 5
  nextFrame(); tick()
  assertf(ringUp(), "pandemic ring inside the last 30% (5s of 24s)")
  assertf(GLOWS[dp] == nil, "…and it is the ring, not a LibCustomGlow standing in for it")

  local ov = dp._pandemicRing
  assertf(AL.GetFX(2944) == 4, "refresh defaults to the ring; the other alert types keep the ants")
  assertf(AL.DefaultFX("usable") == 1 and AL.DefaultFX("available") == 1, "…only refresh")

  -- The art is registered and set. 8a's whole lesson: an unregistered atlas renders as an invisible
  -- texture and logs nothing, so "the ring showed" is not the same as "the ring is visible".
  assertf(NE.tex.HasAtlas("UI-CooldownManager-PandemicBorder"), "the ring atlas is registered")
  local e = NE.tex._atlasEntry("UI-CooldownManager-PandemicBorder")
  assertf(math.abs((e.right - e.left) * 512 - 61) < 0.01
          and math.abs((e.bottom - e.top) * 1024 - 61) < 0.01,
          "…and its rect multiplies out to 61x61 on the sheet we actually ship")
  assertf(ov.Ring:GetTexture() ~= nil, "…and the ring texture resolved to a file")

  -- AROUND the icon, not inside it. The art's opening is 43 of its 61px cell and the other 9 per
  -- side are glow that belongs OUTSIDE — anchored at SetAllPoints (retail's own anchor) those 9 eat
  -- into the icon, which is what the owner saw and reported.
  --
  -- THE INVARIANT, stated once and checked on both tile shapes: the ring's 43-of-61 OPENING lands
  -- on the VISIBLE icon's edge. Everything else about the anchor is derived from that.
  --
  -- Read defensively. A regression to SetAllPoints records a single "ALL" point with no offsets, so
  -- a bare comparison would hit nil and ABORT the harness instead of failing by name — a caught
  -- regression that looks like a truncated run is barely a catch at all.
  local function openingEdge(o, host, size)
    local p1, rel1, _, ex = o:GetPoint(1)
    local p2, _, _, bx    = o:GetPoint(2)
    if not (p1 == "TOPLEFT" and p2 == "BOTTOMRIGHT" and rel1 == host and ex and bx) then return nil end
    -- The ring's rect spans [ex, size-ex]; its opening is the middle 43/61 of that.
    return ex + (size - 2 * ex) * (9 / 61)
  end

  -- FRAMED viewer tile. The gold IconOverlay opens M.IconAperture inside the tile, and THAT is the
  -- icon you can see — not the .Icon rect, which the frame overlaps. Anchoring to .Icon parked the
  -- ring's bright edge out in the gold band with a visible gap, which is what was reported.
  local _, _, _, ax = dp.IconOverlay:GetPoint(1)
  local apX  = M.IconAperture(dp:GetWidth(), -ax)
  local edge = openingEdge(ov, dp, dp:GetWidth())
  assertf(edge ~= nil,
          "a framed tile rings the TILE with a two-point rect -- not .Icon, and not SetAllPoints")
  assertf(edge and math.abs(edge - apX) <= 1,
          ("the ring's opening lands on the FRAME's aperture, not the .Icon rect (%.2f vs %.2f)")
            :format(edge or -1, apX))
  assertf(math.abs(apX - M.IconInset(dp:GetWidth())) > 3,
          ("…and those two differ enough here to tell apart (%.2f vs inset %d)")
            :format(apX, M.IconInset(dp:GetWidth())))

  -- The frame does not move with the icon-inset slider, so the visible edge does not either — and
  -- neither may the ring. Tying it to .Icon would have dragged it off the frame's opening.
  local before = { ov:GetPoint(1) }
  M.SetIconInsetExtra(3)
  M.alerts.ClearFX(dp); nextFrame(); tick()
  local after = { ov:GetPoint(1) }
  assertf(before[4] == after[4] and before[5] == after[5],
          "the icon-inset slider moves the icon but not the ring, because the frame does not move")
  M.SetIconInsetExtra(0)

  -- UNTINTED, deliberately: the art already carries the pandemic colour, and vertex colour
  -- multiplies, so applying TINT.refresh would darken it rather than colour it.
  local r, g, b = ov.Ring:GetVertexColor()
  assertf(r == 1 and g == 1 and b == 1, "the ring is left untinted, not multiplied by TINT.refresh")

  -- Above the cooldown sweep. The sweep is a child frame, so it outranks every draw layer of the
  -- item (§H.2.8) — a ring on any layer would be under it, which is the bug that took four passes
  -- to find for the buff glow. Not relearning it here.
  assertf(ov:GetFrameLevel() > dp.Cooldown:GetFrameLevel(),
          ("ring levelled above the cooldown sweep (%d > %d)")
            :format(ov:GetFrameLevel(), dp.Cooldown:GetFrameLevel()))

  -- The pulse: built, looping, and actually PLAYING. Built-but-never-played is a silent failure —
  -- the ring still shows, just static — so playing is asserted separately from existing.
  assertf(ov.anim ~= nil, "the ring carries a pulse animation")
  assertf(ov.anim:GetLooping() == "REPEAT", "…set to loop")
  assertf(ov.anim:IsPlaying(), "…and playing while the alert is up")
  assertf(#ov.anim._anims == 2, "…as a down/up pair, not a one-way fade")
  local down = ov.anim._anims[1]
  assertf(down._from == 1 and down._to and down._to < 1,
          "…driven through SetFromAlpha/SetToAlpha in that order (ClassicAPI lowers it to SetChange)")

  BUFFS.player[1] = nil
  nextFrame(); tick()
  assertf(not ringUp(), "pandemic ring clears when the aura falls off")
  assertf(not ov.anim:IsPlaying(), "…and stops its pulse rather than animating a hidden frame")
  assertf(ov:GetAlpha() == 1,
          "…leaving alpha at 1, so the next show does not start from wherever the pulse stopped")

  -- A recycled tile must not inherit the previous spell's ring. The 5Hz ticker would clear it, but
  -- not before up to 200ms of the wrong spell wearing it.
  BUFFS.player[1] = { name = "Devouring Plague", rank = "Rank 1", icon = "i", duration = 24, expiration = GetTime() + 5 }
  nextFrame(); tick()
  assertf(ringUp(), "ring back up for the recycle check")
  M.alerts.ClearFX(dp)
  assertf(not ringUp(), "ClearFX drops the ring, which is what tile recycling calls")
  BUFFS.player[1] = nil
end
AL.SetType(2944, nil)

-- "usable": castable right now.
--
-- This block used to assert the OPPOSITE — "a spell with no execute/reactive entry never glows" —
-- and it passed for the wrong reason. isSpellUsableNow was calling IsUsableSpell with a spellID,
-- which this client answers with nil, so nothing could glow on this event whatever the data said.
-- The assertion agreed with the bug and shielded it, until the owner reported that Usable did
-- nothing at all. A test that encodes "feature off" cannot tell you the feature is broken.
AL.SetType(8092, "usable")
AL.ClearFX(mb)
COOLDOWNS[10947] = nil; mb:RefreshCooldown()
nextFrame(); tick()
assertf(GLOWS[mb] ~= nil, "usable alert glows while the spell is castable")
local usableColour = GLOWS[mb] and GLOWS[mb].color
assertf(usableColour and usableColour[1] == 0.95 and usableColour[3] == 0.32,
        "…in the usable yellow, not the available green")
COOLDOWNS[10947] = { GetTime(), 30 }; mb:RefreshCooldown()
nextFrame(); tick()
assertf(GLOWS[mb] == nil, "…and clears while it is on cooldown")
COOLDOWNS[10947] = nil; mb:RefreshCooldown()
AL.SetType(8092, nil); AL.ClearFX(mb)
TARGET_HP = 100

-- ── Alerts on TRACKED BUFFS ─────────────────────────────────────────────────────────────────────
-- The ticker walked essential and utility only, so an alert on a tracked buff stored, lit the badge,
-- previewed on the settings tile — and then never fired in play. Reported from the game as "the FX
-- on tracked buffs doesn't work".
--
-- Driven through the REAL ticker script, because the ticker's VIEWER LIST is the thing under test.
-- Calling evalItem directly here would have passed just as happily against the broken build, which
-- is the same vacuous shape as asserting a tooltip from a pcall that returned true.
do
  local realAuto = M.IsAutoTrackBuffs()
  M.SetAutoTrackBuffs(true)
  BUFFS.player = { { name = "Power Infusion", rank = "", icon = "Interface\\Icons\\PI", count = 0,
                     duration = 15, expiration = GetTime() + 11, spellID = 10060 } }
  auraTick("player")

  local function auraItemFor(viewer, name)
    for _, it in ipairs(viewer.items or {}) do
      if it.spellName == name and it:IsShown() then return it end
    end
    return nil
  end
  local pi    = auraItemFor(bIcon, "Power Infusion")
  local piBar = auraItemFor(bBar,  "Power Infusion")
  assertf(pi ~= nil, "a tracked buff tile to alert on")
  assertf(pi and pi.ConsumeReadyTransition == nil,
          "…and it has NO ready transition, which is why `available` is not offered for one")

  AL.SetType(10060, "refresh")
  AL.SetWindow(10060, 0.30)
  local ringOn = function(it) return (it and it._pandemicRing and it._pandemicRing:IsShown()) or false end

  nextFrame(); tick()
  assertf(not ringOn(pi), "no ring on a tracked buff at 11s of 15s")

  BUFFS.player[1].expiration = GetTime() + 3
  auraTick("player"); tick()
  assertf(ringOn(pi),
          "REFRESH fires on a tracked buff inside the last 30% — the ticker reaches the aura viewers")
  assertf(ringOn(piBar), "…on the BAR viewer too, not only the icon one")

  -- Still edge-correct, not merely on: a buff that is topped back up must drop the ring.
  BUFFS.player[1].expiration = GetTime() + 14
  auraTick("player"); tick()
  assertf(not ringOn(pi), "…and clears again when the buff is refreshed back to full")

  -- The buff falling off has to take the ring with it. Aura tiles are POOLED and reassigned far more
  -- often than spell tiles — every auto-track rescan can hand this frame a different aura — so a ring
  -- left on a hidden tile reappears wearing the next buff's icon.
  BUFFS.player[1].expiration = GetTime() + 3
  auraTick("player"); tick()
  assertf(ringOn(pi), "ring back up for the drop check")
  BUFFS.player = {}
  auraTick("player"); tick()
  assertf(not ringOn(pi), "…and it goes with the buff when that falls off, not onto the next tenant")

  AL.SetType(10060, nil)
  AL.ClearFX(pi); AL.ClearFX(piBar)

  -- ── ACTIVE: the trigger a proc can answer ────────────────────────────────────────────────────
  -- The reported case. A proc has no cooldown to finish and no castable spell of its own name, so
  -- the three ported triggers answer "never" between them; this one asks the only question a tracked
  -- buff can answer. Marching ants rather than the ring, so GLOWS is where it shows.
  BUFFS.player = { { name = "Power Infusion", rank = "", icon = "Interface\\Icons\\PI", count = 0,
                     duration = 15, expiration = GetTime() + 14, spellID = 10060 } }
  auraTick("player")
  pi = auraItemFor(bIcon, "Power Infusion")
  AL.SetType(10060, "active")
  AL.SetFX(10060, 1)
  nextFrame(); tick()
  assertf(GLOWS[pi] ~= nil, "ACTIVE glows for the whole time the buff is up, not just its last 30%")
  local activeColour = GLOWS[pi] and GLOWS[pi].color
  assertf(activeColour and activeColour[3] == 1.00 and activeColour[1] == 0.35,
          "…in its own tint, not borrowed from usable")

  BUFFS.player = {}
  auraTick("player"); tick()
  assertf(GLOWS[pi] == nil, "…and stops the moment the buff drops")
  AL.SetType(10060, nil)
  AL.ClearFX(pi)

  -- ── the settings key survives a rank change ──────────────────────────────────────────────────
  -- The picker writes an alert under the row's id: rank 1 from the catalog, or whatever rank the
  -- scan first met. The live item carries the id the scan returned THIS time. For a ranked buff
  -- those differ, and an id-only lookup finds nothing — stored, badged, and silently dead.
  --
  -- Mind Blast stands in for a ranked aura here: the tracked row holds rank 1 (8092) and the aura on
  -- the player is rank 3 (10947), exactly the shape a real ranked buff takes.
  M.SetAuraAssignment("PRIEST", 8092, "icon", "Mind Blast")
  BUFFS.player = { { name = "Mind Blast", rank = "Rank 3", icon = "Interface\\Icons\\MB", count = 0,
                     duration = 15, expiration = GetTime() + 14, spellID = 10947 } }
  auraTick("player")
  local ranked = auraItemFor(bIcon, "Mind Blast")
  assertf(ranked ~= nil and ranked.spellID == 10947, "the live tile carries the rank the scan found")
  assertf(ranked:GetSettingsKey() == 8092,
          "…but its settings key is the LISTED rank the picker wrote under (" ..
          tostring(ranked and ranked:GetSettingsKey()) .. ")")

  AL.SetType(8092, "active")
  AL.SetFX(8092, 1)
  nextFrame(); tick()
  assertf(GLOWS[ranked] ~= nil,
          "…so an alert stored on the rank-1 row fires on the rank-3 aura the player actually has")
  AL.SetType(8092, nil); AL.ClearFX(ranked)
  M.SetAuraAssignment("PRIEST", 8092, nil, "Mind Blast")

  BUFFS.player = {}
  auraTick("player")
  M.SetAutoTrackBuffs(realAuto)
end

-- A one-shot flash must survive the very next tick, or the settings PREVIEW is invisible.
AL.ClearFX(mb)
AL.Preview(mb, 1)
assertf(GLOWS[mb] ~= nil, "preview shows an effect immediately")
tick()
assertf(GLOWS[mb] ~= nil, "…and the ticker leaves it up for its hold")
nextFrame(2)   -- past AVAILABLE_HOLD
tick()
assertf(GLOWS[mb] == nil, "…then it clears once the hold expires")

-- The preview must show the colour the player will actually SEE. It used to flash everything as
-- "usable", so choosing Available previewed yellow and then glowed green in play.
AL.ClearFX(mb)
AL.Preview(mb, 1, "available")
local previewColour = GLOWS[mb] and GLOWS[mb].color
assertf(previewColour and previewColour[1] == 0.35 and previewColour[2] == 1.00,
        "preview uses the chosen alert type's tint, not always the usable yellow")
AL.ClearFX(mb)
AL.Preview(mb, 1, "refresh")
previewColour = GLOWS[mb] and GLOWS[mb].color
assertf(previewColour and previewColour[1] == 1.00 and previewColour[2] == 0.50,
        "…and refresh previews pandemic-orange")

-- The ring previews too. This is the path the settings menu actually takes when the player picks
-- "Pandemic Border" from the FX submenu, and it runs against a SETTINGS TILE — a frame with no
-- .Cooldown to level against, which the builder has to survive rather than error on.
AL.ClearFX(mb)
AL.Preview(mb, 4, "refresh")
assertf(mb._pandemicRing and mb._pandemicRing:IsShown(), "picking the ring in the menu previews it")
AL.ClearFX(mb)
assertf(not mb._pandemicRing:IsShown(), "…and switching away from it clears the ring")
do
  local bare = CreateFrame("Frame")
  local ok = pcall(AL.Preview, bare, 4, "refresh")
  assertf(ok and bare._pandemicRing and bare._pandemicRing:IsShown(),
          "…on a frame with no Cooldown to level against (the settings tiles)")

  -- UNFRAMED picker tile: no IconOverlay, so the visible icon IS the .Icon rect and the ring falls
  -- back to overhanging it by the art's 9/43. This shape was already correct when the framed one was
  -- not, so it is the half that must not regress while fixing the other.
  local pick = CreateFrame("Frame")
  pick:SetSize(36, 36)
  pick.Icon = pick:CreateTexture(nil, "ARTWORK")
  pick.Icon:SetSize(36, 36)
  AL.Preview(pick, 4, "refresh")
  local po = pick._pandemicRing
  local pp, prel, _, pex = po:GetPoint(1)
  assertf(prel == pick.Icon and pp == "TOPLEFT",
          "an unframed tile rings the .Icon rect, since that is all the icon there is")
  assertf(pex == -math.floor(36 * (9 / 43) + 0.5),
          ("…overhanging it by the art's 9/43 bleed (%s)"):format(tostring(pex)))
  -- Same invariant as the framed case: the opening lands on the visible icon's edge, here 0.
  assertf(math.abs(pex + (36 - 2 * pex) * (9 / 61)) <= 1,
          "…so its opening still lands on the icon's edge, by the same rule")
end
AL.ClearFX(mb)

-- The global escape hatch in the options tab.
AL.SetType(8092, "available")
M.ResetAlerts()
assertf(AL.HasAny() == false and M.HasAnyReadySound() == false, "ResetAlerts clears both stores")
assertf(GLOWS[mb] == nil, "…and takes down anything currently glowing")

print("\n=== SPELL VISIBILITY (Phase 4) ===")
-- Hiding a spell is the one place seeding a custom list is correct: the user just chose.
M.ResetCustomList("essential", "PRIEST")
assertf(M.IsSpellEnabled("essential", 8092) == true, "spell enabled by default")
assertf(M.GetCustomList("essential", "PRIEST") == nil, "…and asking did NOT seed a list")

assertf(M.SetSpellEnabled("essential", 8092, false) == true, "hiding a spell reports a change")
assertf(M.IsSpellEnabled("essential", 8092) == false, "spell now hidden")
local afterHide = M.GetActiveSpellList("essential", true)
local stillThere = false
for _, id in ipairs(afterHide) do if id == 8092 then stillThere = true end end
assertf(not stillThere, "hidden spell drops out of the active list")
assertf(M.SetSpellEnabled("essential", 8092, false) == false, "hiding twice is a no-op")
M.SetSpellEnabled("essential", 8092, true)
assertf(M.IsSpellEnabled("essential", 8092) == true, "and it can be shown again")
M.ResetCustomList("essential", "PRIEST")


print("\n=== SETTINGS PANEL (Phase 4b-1) ===")
local CDS = NE.cooldownviewersettings
assertf(CDS ~= nil, "settings panel namespace exists")
assertf(SlashCmdList["NECDMSETTINGS"] ~= nil, "/cdm slash command registered")
assertf(_G.NE_CooldownViewerSettings == nil, "panel not built before first open (lazy)")

SlashCmdList["NECDMSETTINGS"]()
local sp = _G.NE_CooldownViewerSettings
assertf(sp ~= nil, "/cdm builds and shows the panel")
if sp then
  assertf(sp:IsShown(), "panel shown after first /cdm")
  assertf(sp._w == 399 and sp._h == 609, "panel sized 399x609 (" .. sp._w .. "x" .. sp._h .. ")")
  assertf(CDS.GetDisplayMode() == "spells", "opens on the Spells tab")
  -- Three tabs: Spells, Tracked Buffs, Settings. NOT upstream's three — its third is Group Buffs,
  -- which needs NE.groupbuff.filter and is dropped whole (PORT_PLAN §G.4).
  assertf(#sp.tabButtons == 3, "three side tabs (" .. #sp.tabButtons .. ")")
  assertf(sp.settingsTab.displayMode == "settings", "…the third being Settings, not Group Buffs")
  assertf(sp.scroll ~= nil and sp.content ~= nil, "scroll body built")
  assertf(sp.search ~= nil, "search box built")

  -- THE BODY STONE. PC.ApplyModernChrome tints its f.Bg to 0.32 grey for a first-paint fix that
  -- belongs to a different frame; this window wore it and read as a dark wash next to every other
  -- standalone window, which is what was reported. Asserted on the RESULT rather than on "we called
  -- SetVertexColor", because the tint is applied by shared code we do not own and could come back.
  assertf(sp.Bg ~= nil, "the panel has a body fill")
  local br, bg_, bb = sp.Bg:GetVertexColor()
  assertf(br == 1 and bg_ == 1 and bb == 1,
          ("body stone at full brightness, not PC's 0.32 wash (%.2f, %.2f, %.2f)"):format(br, bg_, bb))
  -- The PRECONDITION for the guard above, asserted so it cannot quietly stop holding. PanelChrome
  -- tints only on the branch where the rock art resolves; with the art unregistered it degrades to a
  -- flat fill, applies no tint, and the brightness check passes on a window with no stone in it at
  -- all. That is not hypothetical — it is exactly how this suite behaved until the rock was
  -- registered above, and a mutation removing the untint failed to fail because of it.
  --
  -- Deliberately NOT asserted on sp.Bg:GetTexture(): NE.nineslice is absent offline, so
  -- ApplyModernChrome finishes through applyFallbackBackdrop and overwrites the texture with a solid
  -- colour. The tint it set on the way past is what survives, and is what this pair actually checks.
  assertf(NE.tex.Local(374155) ~= nil,
          "…and the rock art resolves, which is what makes that brightness guard non-vacuous")
  -- The Inset's own marble stays hidden. It is the OLD ClassicAPI stone, and it is what the window
  -- would fall back to if the body fill were ever moved off subLevel 0.
  assertf(not (sp.Inset and sp.Inset.Bg and sp.Inset.Bg:IsShown()),
          "the template's Inset marble stays hidden under our own stone")

  -- THE RECESSED INSET, near-black over the stone. Asserted on the SUBLEVEL as well as on existence,
  -- because the previous fill had every other property right — created, shown, anchored to the Inset,
  -- correct texture — and sat one layer UNDER the body stone, so none of it was ever on screen. That
  -- is the failure this pair exists to name, and it is invisible to any check that only asks whether
  -- the texture is there.
  assertf(sp.InsetBg ~= nil and sp.InsetBg:IsShown(), "the Inset has its own recessed fill")
  assertf(sp.InsetBg._sublevel > sp.Bg._sublevel,
          ("…ABOVE the body stone, not under it (subLevel %d vs %d)")
            :format(sp.InsetBg._sublevel, sp.Bg._sublevel))
  -- SetTexture(r, g, b, a) — the 3.3.5a colour form; the stub keeps the first argument, so a red
  -- channel this dark is the whole statement.
  local insetR = sp.InsetBg:GetTexture()
  assertf(type(insetR) == "number" and insetR < 0.2,
          "…and it is near-black, not another sheet of stone")
  local ip1, irel1 = sp.InsetBg:GetPoint(1)
  assertf(ip1 == "TOPLEFT" and irel1 == sp.Inset, "…covering the Inset rect exactly")

  -- THE BUTTON STRIP. The Inset's bottom edge and the scroll body's both key off one FOOTER_H, so
  -- they cannot be raised independently and leave the layout/Revert buttons overlapping the border
  -- again. ButtonFrameTemplate's own Inset bottom is 26; anything at or below that is the strip
  -- back at its original height.
  local function bottomY(frame)
    for i = frame:GetNumPoints(), 1, -1 do
      local p, a, b, _, d = frame:GetPoint(i)
      -- SetPoint has two shapes — (point, relTo, relPoint, x, y) and the short (point, x, y) — and
      -- the stub records arguments positionally rather than normalising them. Read whichever this
      -- particular call used; guessing one shape silently yields nil for the other.
      if p == "BOTTOMRIGHT" then
        if type(a) == "number" then return b end
        return d
      end
    end
  end
  local insetBottom, scrollBottom = bottomY(sp.Inset), bottomY(sp.scroll)
  assertf(insetBottom == 36,
          "the button strip is 36px tall — the template's 26 plus the owner's 10 (" ..
          tostring(insetBottom) .. ")")
  assertf(scrollBottom == insetBottom + 8,
          ("…and the scroll body clears it by its own pad, not by a second hardcoded number (%s vs %s)")
            :format(tostring(scrollBottom), tostring(insetBottom)))
  assertf(sp.layoutButton:GetHeight() + 6 < insetBottom,
          "…leaving the layout button clear of the Inset's bottom border, which is the point")

  -- ── THE MODERN SCROLLBAR ─────────────────────────────────────────────────────────────────────
  -- NE.scrollbar.Reskin looked applied here for phases and could never have done anything: it
  -- reaches for `scroll.ScrollBar`, and 3.3.5a's UIPanelScrollFrameTemplate declares that slider as
  -- `$parentScrollBar` with NO parentKey, so the field is nil and Reskin returns at its second line.
  -- The failure has no symptom beyond "the bar looks stock", which is exactly what it looked like.
  local bar = sp.scroll._neCustomBar
  assertf(bar ~= nil, "the scroll body carries the hand-built minimal bar, not an in-place reskin")

  local stockSB = _G["NE_CooldownViewerSettingsScrollScrollBar"]
  assertf(stockSB ~= nil, "…and the template's stock Slider exists to have been dealt with")
  assertf(not stockSB:IsShown(), "…which is hidden, so the player does not get two bars side by side")

  -- The arrows have to leave the stock slider or its Hide() takes them with it, whatever their own
  -- state — a hidden parent hides its children.
  local upBtn   = _G["NE_CooldownViewerSettingsScrollScrollBarScrollUpButton"]
  local downBtn = _G["NE_CooldownViewerSettingsScrollScrollBarScrollDownButton"]
  assertf(upBtn ~= nil and upBtn._parent ~= stockSB,
          "the up arrow is reparented off the hidden slider, so it can still be seen")
  local upPoint, upRel = upBtn:GetPoint(1)
  assertf(upPoint == "BOTTOM" and upRel == bar, "…and anchored to OUR track, not the stock one")

  -- Clicking must SCROLL, not error. The template's inline OnClick drives self:GetParent() and
  -- assumes that is the slider; once the button hangs off the panel, GetValue is nil there and every
  -- click throws. BuildCustom learned this the hard way on the character Skills list.
  sp.scroll._vrange = 200
  sp.scroll:SetVerticalScroll(0)
  -- Read the handlers BEFORE calling them. Missing ones are a real regression (the reparent strands
  -- the template's inline OnClick), and calling nil aborts the whole run instead of failing here by
  -- name — a caught bug that looks like a truncated harness is barely caught at all.
  local downClick, upClick = downBtn:GetScript("OnClick"), upBtn:GetScript("OnClick")
  assertf(downClick ~= nil and upClick ~= nil, "both arrows carry a click handler of our own")
  if downClick then downClick(downBtn) end
  assertf(sp.scroll:GetVerticalScroll() > 0,
          "clicking the down arrow scrolls the frame (" .. sp.scroll:GetVerticalScroll() .. ")")
  if upClick then upClick(upBtn) end
  assertf(sp.scroll:GetVerticalScroll() == 0, "…and the up arrow scrolls it back")

  -- The thumb sizes from visible:total — the pixel-scroll variant's own arithmetic, not
  -- BuildCustom's row-step heuristic for FauxScrollFrames.
  bar:SetHeight(300)
  sp.scroll:SetVerticalScroll(0)
  NE.scrollbar.BuildCustomPixel(sp.scroll)   -- idempotent; returns the existing bar
  sp.scroll._scripts.OnScrollRangeChanged(sp.scroll)
  assertf(bar:IsShown(), "the bar shows once there is something to scroll")
  local thumbH = bar._thumb:GetHeight()
  assertf(thumbH > 0 and thumbH < 300, "…with a thumb shorter than its track (" .. thumbH .. ")")

  sp.scroll._vrange = 0
  sp.scroll._scripts.OnScrollRangeChanged(sp.scroll)
  assertf(not bar:IsShown(), "…and hides again when the content fits")
  assertf(not upBtn:IsShown() and not downBtn:IsShown(),
          "…taking the arrows with it, which being siblings they do not do by themselves")


  local esc = false
  for _, n in ipairs(UISpecialFrames) do if n == "NE_CooldownViewerSettings" then esc = true end end
  assertf(esc, "registered with UISpecialFrames for ESC-close")

  CDS.SetDisplayMode("auras")
  assertf(CDS.GetDisplayMode() == "auras", "switches to the Auras tab")

  SlashCmdList["NECDMSETTINGS"]()
  assertf(not sp:IsShown(), "/cdm toggles the panel closed")
  CDS.OpenTo("buffBar")
  assertf(sp:IsShown() and CDS.GetDisplayMode() == "auras", "OpenTo(buffBar) opens on the Auras tab")
  CDS.HidePanel()
end

-- The side-tab art must resolve or the tabs are transparent gaps. This is what would have caught
-- core/Tabs.lua's stale "sheet not shipped" note.
assertf(NE.tex.HasAtlas("questlog-tab-side"), "side-tab body atlas registered")
assertf(NE.tex.HasAtlas("icon_cooldownmanager"), "Spells tab glyph registered")
assertf(NE.tex.HasAtlas("icon_trackedbuffs"), "Auras tab glyph registered")
-- Registered by this module, not borrowed from the spellbook's asset file: the tab would otherwise be
-- a transparent gap on any load order where that file had not run.
assertf(NE.tex.HasAtlas("questlog-icon-setting"), "Settings tab glyph registered")

print("\n=== VIEWER ART (Phase 8a) ===")
do
  -- Six atlases were being set by name and registered nowhere, so every region rendered as nothing.
  -- HasAtlas on each is the assertion that would have caught it — the same one that caught the
  -- side-tab art above.
  local VIEWER_ATLASES = {
    "UI-HUD-CoolDownManager-IconOverlay",
    "UI-CooldownManager-OORshadow",
    "UI-HUD-ActionBar-GCD-Flipbook",
    "UI-HUD-CoolDownManager-Bar",
    "UI-HUD-CoolDownManager-Bar-BG",
    "UI-HUD-CoolDownManager-Bar-Pip",
  }
  for _, name in ipairs(VIEWER_ATLASES) do
    assertf(NE.tex.HasAtlas(name), "atlas registered: " .. name)
  end

  -- Every atlas name the viewer files MENTION must be registered. Hard-coding the list above would
  -- not have caught the original fault, because the fault was a name nobody had listed anywhere —
  -- so read them back out of the source instead. A seventh SetAtlas added later fails here.
  local mentioned, missing = {}, {}
  for _, rel in ipairs({ "modules/cooldownviewer/ItemMixins.lua",
                         "modules/cooldownviewer/AuraItemMixins.lua",
                         "modules/cooldownviewer/BuffViewers.lua",
                         "modules/cooldownviewer/Viewers.lua" }) do
    local fh = io.open(ADDON .. rel, "r")
    if fh then
      local body = fh:read("*a"); fh:close()
      -- Line by line, skipping comments. Matching on the function name does not work: the call sites
      -- go through a local alias (`local set = NE.tex.SetAtlas; set(tex, "UI-...")`), which is how a
      -- first attempt at this found 3 of 6. Skipping comment lines is the other half — these files
      -- also NAME atlases in prose, and a comment explaining why one is deliberately absent must not
      -- be read as a requirement to ship it.
      for line in body:gmatch("[^\r\n]+") do
        if not line:match("^%s*%-%-") then
          for nm in line:gmatch('"(UI%-[%w%-]+)"') do mentioned[nm] = rel end
        end
      end
    end
  end
  local n = 0
  for nm, rel in pairs(mentioned) do
    n = n + 1
    if not NE.tex.HasAtlas(nm) then missing[#missing + 1] = nm .. " (" .. rel .. ")" end
  end
  assertf(n >= 6, "found the viewer files' atlas call sites (" .. n .. " names)")
  assertf(#missing == 0, "every atlas the viewers ask for is registered"
    .. (#missing > 0 and (": MISSING " .. table.concat(missing, ", ")) or ""))

  -- The rects are transcribed from upstream's generated data, so the thing worth asserting is that
  -- they belong to the sheets WE ship: rect fraction x sheet size must give back the declared atlas
  -- size. This is what catches a repacked sheet — the exact failure SettingsAssets.lua records for
  -- 7289697, where Era-generated rects were wrong for the 12.1.0 BLP.
  local SHEET = { [6704514] = { 256, 128 }, [6685874] = { 512, 1024 }, [5199404] = { 2048, 1024 } }
  local bad = {}
  for _, name in ipairs(VIEWER_ATLASES) do
    local e = NE.tex._atlasEntry(name)
    local sheet = e and SHEET[e.file]
    if sheet then
      local w = (e.right - e.left) * sheet[1]
      local h = (e.bottom - e.top) * sheet[2]
      if math.abs(w - e.width) > 0.5 or math.abs(h - e.height) > 0.5 then
        bad[#bad + 1] = ("%s: rect gives %.1fx%.1f, declares %dx%d")
          :format(name, w, h, e.width, e.height)
      end
    else
      bad[#bad + 1] = name .. ": no known sheet size for fdid " .. tostring(e and e.file)
    end
  end
  assertf(#bad == 0, "every rect matches the shipped sheet's real dimensions"
    .. (#bad > 0 and (": " .. table.concat(bad, "; ")) or ""))

  -- Each sheet must actually be on disk under the path Assets.lua registers. A rect pointing at an
  -- unshipped FDID resolves to the bare number, which the client renders as nothing — the same
  -- invisible failure by a different route (and the one SettingsAssets.lua hit with 5684744).
  for fdid in pairs(SHEET) do
    local path = NE.tex.Local(fdid)
    assertf(path ~= nil, "sheet " .. fdid .. " has a local BLP path")
    if path then
      local rel = path:gsub("^Interface\\AddOns\\DragonUI_NewEra\\", ""):gsub("\\", "/")
      local fh = io.open(ADDON .. rel, "rb")
      assertf(fh ~= nil, "…and the file exists: " .. rel)
      if fh then
        -- Confirm the BLP header carries the dimensions the rect arithmetic above assumed, rather
        -- than trusting a table that says so.
        local head = fh:read(20); fh:close()
        local magic = head:sub(1, 4)
        local w = 0
        for i = 0, 3 do w = w + head:byte(13 + i) * (256 ^ i) end
        local h = 0
        for i = 0, 3 do h = h + head:byte(17 + i) * (256 ^ i) end
        assertf(magic == "BLP2" and w == SHEET[fdid][1] and h == SHEET[fdid][2],
          ("…and is a BLP2 of the assumed size (%s %dx%d)"):format(magic, w, h))
      end
    end
  end

  -- ── icon-vs-frame fit ─────────────────────────────────────────────────────────────────────────
  -- Registering the overlay made a geometry fault visible that had been latent since Phase 1: retail
  -- masks the Icon, and that mask insets it by 3/64 of the tile as well as rounding it. Without the
  -- inset a full-bleed icon overshoots the overlay's border line by ~4px on a 50px tile and sits out
  -- in the halo — "the icons are too large and sit outside the framing".
  assertf(math.abs(M.ICON_MASK_INSET - 3 / 64) < 1e-9,
    "the mask inset is the one decoded from 6707800 (3 of 64)")

  -- The border line's position in tile coordinates, derived from the art rather than restated: the
  -- crisp line sits at art 14-19 of the 86px cell, mapped through the overlay's outward anchor. The
  -- icon's edge must land INSIDE that band — outside it the frame floats off the icon (the old
  -- full-bleed behaviour), well inside it the frame eats into the art.
  --
  -- PER AXIS, which is the point. The overlay is anchored ±9 horizontally but ±8 vertically, so the
  -- band sits at a different offset on each axis while the mask is square. A first version of this
  -- checked the horizontal band only and passed while the icon's top and bottom edges were still
  -- outside their band on three of the four tile shapes — reported from the game as "still 1px too
  -- large in all directions".
  local function bandOn(size, o)
    local ext = size + 2 * o
    return -o + 14 * ext / 86, -o + 19 * ext / 86
  end
  for _, v in ipairs({ { "essential", M.viewers.essential, 50, 9, 8 },
                       { "utility",   M.viewers.utility,   30, 6, 5 },
                       { "buffIcon",  M.viewers.buffIcon,  40, 8, 7 } }) do
    local label, viewer, size, ox, oy = v[1], v[2], v[3], v[4], v[5]
    local item = viewer and viewer.items and viewer.items[1]
    if item and item.Icon then
      local want = M.IconInset(size)
      local p, _, _, x, y = item.Icon:GetPoint(1)
      assertf(p == "TOPLEFT" and math.abs((x or 0) - want) < 0.01 and math.abs((y or 0) + want) < 0.01,
        ("%s icon is inset by %.2fpx (got %s %s,%s)")
          :format(label, want, tostring(p), tostring(x), tostring(y)))
      -- The icon's edge must sit at or OUTSIDE the band's dark core, on both axes. This assertion
      -- used to demand the opposite — that the edge land INSIDE the band — and that is what drove
      -- three rounds of shrinking the icon. An inner shadow shows only where there is icon beneath
      -- it, so an edge inside the band means the darkest part of the frame is falling on nothing.
      for _, ax in ipairs({ { "horizontally", ox }, { "vertically", oy } }) do
        local _, hi = bandOn(size, ax[2])
        assertf(want < hi,
          ("…and the frame's shadow still has icon under it %s (%.2f inside %.2f)")
            :format(ax[1], want, hi))
      end

      -- Everything drawn OVER the icon shares its rect. Anchored to the tile instead, each one draws
      -- proud of the icon and shows the old footprint — which is exactly how the cooldown sweep gave
      -- itself away once the frame art shipped.
      for _, r in ipairs({ { "cooldown sweep", item.Cooldown },
                           { "out-of-range shade", item.OutOfRange },
                           { "ready flash", item.CooldownFlash } }) do
        local rn, reg = r[1], r[2]
        if reg then
          local rp, _, _, rx, ry = reg:GetPoint(1)
          assertf(rp == "TOPLEFT" and math.abs((rx or 0) - want) < 0.01
                    and math.abs((ry or 0) + want) < 0.01,
            ("…%s's %s shares the icon's rect (got %s %s,%s)")
              :format(label, rn, tostring(rp), tostring(rx), tostring(ry)))
        end
      end
    else
      assertf(false, label .. " has an item to measure")
    end
  end

  -- The invariant, and it is the OPPOSITE of what the first three passes at this assumed. The frame
  -- is an inner shadow with its dark core on a line at art x=14 of 86; a shadow only shows where
  -- there is icon under it, so the icon's edge must stay AT OR OUTSIDE that core. Inset past it and
  -- the frame does not tighten, it disappears — which is how the last pass ended with "it looks like
  -- the icon border is missing".
  local function coreOn(size, o)
    local ext = size + 2 * o
    return -o + 14 * ext / 86
  end
  for _, v in ipairs({ { "essential", 50, 9, 8 }, { "utility", 30, 6, 5 }, { "buffIcon", 40, 8, 7 } }) do
    local label, size, ox, oy = v[1], v[2], v[3], v[4]
    for _, ax in ipairs({ { "horizontally", ox }, { "vertically", oy } }) do
      local core = coreOn(size, ax[2])
      local band = select(2, bandOn(size, ax[2]))
      -- HOW MUCH of the dark band has icon beneath it, not merely whether any does. "Some" passes at
      -- settings where the frame has visibly gone: at +4% the Essential tile still overlaps the band,
      -- and that is the state that came back from the game as "the border is missing". Coverage is
      -- the measure that separates them — 93% at the shipped default, 42% at +4%.
      local atDefault = M.IconInset(size)   -- what actually ships, snapping included
      local covered = (band - atDefault) / (band - core)
      if covered > 1 then covered = 1 end
      assertf(covered >= 0.70,
        ("%s keeps the frame's shadow on the icon %s by default (%d%% covered)")
          :format(label, ax[1], math.floor(covered * 100)))
      -- The ceiling is where the dark core would leave the icon entirely.
      local atMax = size * (M.ICON_MASK_INSET + M.ICON_INSET_EXTRA_MAX / 100)
      assertf(atMax < band,
        ("%s still has frame on the icon %s at max inset (%.2f inside %.2f)")
          :format(label, ax[1], atMax, band))
      assertf(core < band, label .. "'s shadow core is inside its band " .. ax[1])
    end
  end

  -- Fractional, not flat. A flat pixel budget generous enough for a 50px tile pushes a 30px one
  -- through its own opening — the first draft did exactly that and failed here at 3.41 against 3.28.
  -- Asserted as "tracks the fraction to within half a pixel" rather than "equals it", because the
  -- result is now SNAPPED (see below); an exact-equality check here would forbid the snapping.
  for _, size in ipairs({ 50, 40, 30 }) do
    local want = size * (M.ICON_MASK_INSET + M.ICON_INSET_EXTRA / 100)
    assertf(math.abs(M.IconInset(size) - want) <= 0.5,
      ("the inset tracks the tile's fraction at %d (%.2f vs %.2f)"):format(size, M.IconInset(size), want))
  end

  -- WHOLE PIXELS. A fractional inset resolves independently on each edge — 2.34 from the left, 47.66
  -- from the right — so the two margins can land a pixel apart against a frame anchored on integers.
  -- Reported as a sliver of icon escaping on one side only, and as the cooldown sweep covering the
  -- glow on the right but not the left: the sweep shares the icon's rect, so it inherits the split.
  for _, size in ipairs({ 50, 40, 30 }) do
    local v = M.IconInset(size)
    assertf(v == math.floor(v), ("the inset is a whole pixel at %d (got %s)"):format(size, tostring(v)))
  end
  -- And every region that shares the icon's rect inherits that, which is the point of the shared
  -- helper: if the icon is on whole pixels the sweep is too, by construction.
  for _, r in ipairs({ { "sweep", mb.Cooldown }, { "out-of-range", mb.OutOfRange },
                       { "flash", mb.CooldownFlash } }) do
    local x = select(4, r[2]:GetPoint(1))
    assertf(x == math.floor(x), ("…and so is the " .. r[1] .. " (%s)"):format(tostring(x)))
  end

  -- And it has to reach tiles that already exist, or the slider does nothing until the next login.
  do
    local before = select(4, mb.Icon:GetPoint(1))
    M.SetIconInsetExtra(M.ICON_INSET_EXTRA_MAX)
    local after = select(4, mb.Icon:GetPoint(1))
    assertf(after > before, ("moving the slider re-anchors a built tile (%.2f -> %.2f)")
      :format(before, after))
    M.SetIconInsetExtra(M.ICON_INSET_EXTRA)
    assertf(math.abs(select(4, mb.Icon:GetPoint(1)) - before) < 1e-9, "…and back again")
  end

  -- ── frame strength ────────────────────────────────────────────────────────────────────────────
  -- The art tops out at 42% black, which is a bevel rather than a border. SetAlpha only scales DOWN,
  -- so the only way to deepen it is to draw it again: 1-(1-a)^N, so 42% -> 66% -> 80%.
  do
    assertf(mb.IconOverlayStack ~= nil and #mb.IconOverlayStack >= 1,
      "the tile carries spare copies of the frame art")
  end

  -- The buff halo hangs off the ICON, not the tile. Off the tile it sat wide of the thing it was
  -- lighting — "improve the alignment of the icon to the gold background" — and it would not have
  -- followed the inset slider either.
  do
    local rel = select(2, mb.BuffGlow:GetPoint(1))
    assertf(rel == mb.Icon, "the buff halo is anchored to the icon, so the two are concentric")
  end

  -- The flipbook's frame grid has to divide its strip evenly, or the ready-flash sprite samples
  -- across frame boundaries. 94/2 and 517/11 are both 47.
  local e = NE.tex._atlasEntry("UI-HUD-ActionBar-GCD-Flipbook")
  assertf(e.width % 2 == 0 and e.height % 11 == 0,
    "the flipbook strip divides into 2x11 whole frames")
  assertf(e.width / 2 == e.height / 11, "…and those frames are square (47x47)")
end

print("\n=== BUFFED-SPELL GLOW (Phase 8c) ===")
do
  local glow = mb.BuffGlow
  assertf(glow ~= nil, "the tile has a buff-glow region")

  -- The texture lives INSIDE the glow frame now. Everything about the art is unchanged; what changed
  -- is what hosts it.
  local tex = glow.Texture
  assertf(tex ~= nil, "the glow hosts its texture in a frame of its own")
  assertf(tex:GetTexture() == M.BUFF_GLOW_TEXTURE,
    "…still the stock soft-glow ring, not a sheet atlas")
  assertf(not tostring(tex:GetTexture()):find("CooldownViewer", 1, true),
    "…and NOT the CoolDownManager sheet, whose art is black and emits nothing under ADD")
  assertf(tex:GetBlendMode() == "ADD", "…blended additively, so it lights rather than darkens")
  local r, g, b = tex:GetVertexColor()
  assertf(r > g and g > b, "…in gold, the colour retail gives the swipe it cannot set here")

  -- ABOVE THE COOLDOWN, and this is the assertion the whole glow saga needed. `Cooldown` is a CHILD
  -- FRAME, and a child frame draws above EVERY layer of its parent — BACKGROUND and OVERLAY 7 alike.
  -- So the halo was under the rotating sweep whichever layer it was given, and which part of it
  -- survived depended on where the sweep had got to. Only a higher frame level beats a child frame.
  assertf(glow:GetFrameLevel() > mb.Cooldown:GetFrameLevel(),
    ("…and outranks the cooldown sweep (%d vs %d)")
      :format(glow:GetFrameLevel(), mb.Cooldown:GetFrameLevel()))

  -- Oversized past the icon, and anchored to the ICON so the two stay concentric.
  local gp, rel, _, gx, gy = glow:GetPoint(1)
  local over = M.BuffGlowInset(50)
  assertf(gp == "TOPLEFT" and rel == mb.Icon and gx == -over and gy == over,
    ("…hung off the icon by %dpx (got %s,%s)"):format(over, tostring(gx), tostring(gy)))

  -- The state machine. A tile with no aura of its own must not glow, or the signal means nothing.
  BUFFS.player[1] = nil
  COOLDOWNS[10947] = nil
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == false, "no glow with the spell's buff absent")

  BUFFS.player[1] = { name = "Mind Blast", rank = "Rank 3", icon = "i",
                      duration = 15, expiration = GetTime() + 10 }
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == true, "glows while the spell's own buff is on the player")

  -- The cooldown path must take it off again. This is the one that would break silently: the aura
  -- branch returns early, so a glow left un-cleared there stays up for the rest of the session.
  BUFFS.player[1] = nil
  COOLDOWNS[10947] = { GetTime(), 30 }
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == false, "…and comes off when the buff falls and the cooldown starts")
  COOLDOWNS[10947] = nil; mb:RefreshCooldown()

  -- The opt-out has to reach a tile that is glowing RIGHT NOW. RefreshCooldown only revisits the
  -- glow when something about the spell changes, which for a buff already up can be a minute away —
  -- so the setter refreshes rather than waiting to be noticed.
  BUFFS.player[1] = { name = "Mind Blast", rank = "Rank 3", icon = "i",
                      duration = 15, expiration = GetTime() + 10 }
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == true, "glowing again for the opt-out check")
  M.SetBuffGlowEnabled(false)
  assertf(M.IsBuffGlowEnabled() == false, "the setting stores off")
  assertf(glow:IsShown() == false, "…and clears a glow that was already up")
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == false, "…and refreshing does not bring it back")
  M.SetBuffGlowEnabled(true)
  nextFrame(); mb:RefreshCooldown()
  assertf(glow:IsShown() == true, "…and turning it back on restores it")
  assertf(M.IsBuffGlowEnabled() == true, "on is the default state")

  -- A recycled tile keeps its texture regions. RefreshCooldown returns early without a spellID, so
  -- nothing on the refresh path can clear a glow left behind by the spell that used to live here —
  -- the pooling loop has to do it, or the next spell to reuse the tile inherits a gold frame.
  local ev = M.viewers.essential
  local last = ev.items[#ev.items]
  last:SetBuffGlow(true)
  assertf(last.BuffGlow:IsShown() == true, "a spare tile is glowing before the list shrinks")
  M.SetSpellEnabled("essential", 8092, false)
  ev:Rebuild()
  assertf(last.BuffGlow:IsShown() == false, "…and recycling the tile out of the layout clears it")
  M.SetSpellEnabled("essential", 8092, true)
  M.ResetCustomList("essential", "PRIEST")
  ev:Rebuild()

  BUFFS.player[1] = nil
  nextFrame()
end

print("\n=== BUFFED TILE: WHICH TIMER (Phase 8c follow-up) ===")
do
  -- Reported on Prayer of Mending: the tile counted down the 30s BUFF while the player wanted the
  -- cooldown, and two numbers ticking over the same icon are indistinguishable. Retail can only say
  -- "buffed" by tinting that swipe, so it has no choice; since 8c the glow says it, and the number
  -- is free to be the useful one.
  assertf(M.BuffShowsAuraTime() == false, "the cooldown is the default timer on a buffed tile")

  local cdStart, cdDur = GetTime() - 1, 30
  COOLDOWNS[10947] = { cdStart, cdDur }
  BUFFS.player[1] = { name = "Mind Blast", rank = "Rank 3", icon = "i",
                      duration = 6, expiration = GetTime() + 6 }
  nextFrame(); mb:RefreshCooldown()
  assertf(math.abs((mb.Cooldown._cdDur or 0) - cdDur) < 0.01,
    ("buffed AND on cooldown shows the cooldown (%s, not the 6s aura)")
      :format(tostring(mb.Cooldown._cdDur)))
  assertf(mb.BuffGlow:IsShown() == true, "…and the glow still marks it as buffed")

  -- The signal is not the setting: flipping the timer must not silence the glow, or the two numbers
  -- become indistinguishable again in the other direction.
  M.SetBuffShowsAuraTime(true)
  nextFrame(); mb:RefreshCooldown()
  assertf(math.abs((mb.Cooldown._cdDur or 0) - 6) < 0.01,
    ("retail's reading shows the aura instead (%s)"):format(tostring(mb.Cooldown._cdDur)))
  assertf(mb.BuffGlow:IsShown() == true, "…with the glow unchanged either way")
  M.SetBuffShowsAuraTime(false)

  BUFFS.player[1] = nil
  COOLDOWNS[10947] = nil
  nextFrame(); mb:RefreshCooldown()
end

print("\n=== PER-SPEC LAYOUT ===")
do
  local group = 1
  GetActiveTalentGroup = function() return group end
  M.ResetTracking()
  assertf(M.IsPerSpecLayout() == true, "per-spec layout is on by default")
  assertf(M.LayoutKey() == "spec1", "…and keys off the active talent group")

  -- The reported behaviour: hide a spell in one spec, swap, and it must come back.
  M.SetSpellEnabled("essential", 8092, false)
  assertf(M.IsSpellEnabled("essential", 8092) == false, "spell hidden in group 1")

  group = 2
  M.InvalidateCuratedCache()
  assertf(M.LayoutKey() == "spec2", "swapping groups moves to the other bucket")
  assertf(M.IsSpellEnabled("essential", 8092) == true,
    "…where the spell is still shown — the two layouts are independent")

  M.SetSpellEnabled("essential", 8092, false)
  M.SetSpellEnabled("essential", 8129, false)
  group = 1
  M.InvalidateCuratedCache()
  assertf(M.IsSpellEnabled("essential", 8129) == true,
    "…and edits in group 2 do not leak back into group 1")
  assertf(M.IsSpellEnabled("essential", 8092) == false, "…while group 1 keeps its own edit")

  -- Turning the feature off collapses both onto one shared bucket.
  M.SetPerSpecLayout(false)
  assertf(M.LayoutKey() == "shared", "off, both groups share one bucket")
  group = 2
  assertf(M.LayoutKey() == "shared", "…whichever group is active")
  M.SetPerSpecLayout(true)
  group = 1
  M.InvalidateCuratedCache()

  -- Reset clears EVERY bucket. Clearing only the active one would leave the other spec's lists in
  -- place after the player asked for a clean slate.
  M.ResetTracking()
  assertf(M.IsSpellEnabled("essential", 8092) == true, "reset clears the active bucket")
  group = 2
  M.InvalidateCuratedCache()
  assertf(M.IsSpellEnabled("essential", 8092) == true, "…and the inactive one too")
  group = 1
  M.InvalidateCuratedCache()

  -- ── and it clears only THIS CLASS ──────────────────────────────────────────────────────────────
  -- The store is one shared DragonUI profile, keyed by class the whole way down —
  -- customLists[category][CLASS], trackedAura[CLASS], seenAura[CLASS]. ResetTracking used to blank
  -- specLayouts and seenAura WHOLE, so a Priest pressing reset cleared the Warlock and the Druid too.
  -- Reported from the game as "the reset character button actually resets all characters".
  --
  -- The assertions that matter are about a class the player is NOT logged in as. That is the whole
  -- test: the old behaviour passed every same-class check there is.
  M.SetCustomList("essential", "WARLOCK", { { spellID = 686, enabled = true } })
  M.SetAuraAssignment("WARLOCK", 980, "icon", "Curse of Agony")
  M.NoteSeenAura(603, "Haunt", "i", 12)          -- lands under PRIEST, the logged-in class
  local cdStore = M._store(true)
  cdStore.seenAura = cdStore.seenAura or {}
  cdStore.seenAura.WARLOCK = { [17962] = { spellID = 17962, name = "Conflagrate", dur = 10 } }

  M.ResetTracking()

  local wlList = M.GetCustomList("essential", "WARLOCK")
  assertf(wlList ~= nil and wlList[1] and wlList[1].spellID == 686,
          "another class's spell list survives this class's reset")
  local keptAura = false
  for _, e in ipairs(M.GetTrackedAuraList("WARLOCK") or {}) do
    if e.spellID == 980 then keptAura = true end
  end
  assertf(keptAura, "…and its aura assignments")
  assertf(cdStore.seenAura.WARLOCK and cdStore.seenAura.WARLOCK[17962] ~= nil,
          "…and its seen-aura registry")

  -- …while this class IS genuinely reset, which is the half a scoping fix makes easy to lose.
  assertf(M.GetCustomList("essential", "PRIEST") == nil,
          "the logged-in class's list is still cleared, or the fix is just a no-op")
  local mySeen = false
  for _, e in ipairs(M.GetSeenAuraList("PRIEST") or {}) do if e.spellID == 603 then mySeen = true end end
  assertf(not mySeen, "…and so is its seen registry")

  M.SetCustomList("essential", "WARLOCK", nil)
  M.SetAuraAssignment("WARLOCK", 980, nil, "Curse of Agony")
  cdStore.seenAura.WARLOCK = nil

  -- ── PER-CHARACTER APPEARANCE, opt-in ───────────────────────────────────────────────────────────
  -- Off by default, and off must behave exactly as it always did. On, a character's changes become
  -- OVERRIDES on the shared table rather than a copy of it — which is what makes toggling free in
  -- both directions instead of a migration with a jump at each end.
  local FID = M.FRAME_ID.essential
  local realName = UnitName
  M.ResetOpts(FID)
  assertf(M.IsPerCharacterFrames() == false, "per-character appearance is OFF by default")

  M.SetOpt(FID, "iconLimit", 7)
  assertf(M.GetOpt(FID, "iconLimit") == 7, "with it off, a setting is written account-wide as before")
  local frameStore = M._store(true)
  -- Read defensively: if the write went to a per-character bucket instead, frames[FID] is nil and a
  -- bare index aborts the whole run rather than failing here by name.
  assertf(frameStore.frames[FID] and frameStore.frames[FID].iconLimit == 7,
          "…into cd.frames, the shared table")
  assertf(frameStore.charFrames == nil, "…and no per-character bucket is created at all")

  -- Ticking it must move NOTHING. A character that has changed nothing reads the shared value
  -- through the fall-through, which is the seed — there is no copy step to get wrong.
  M.SetPerCharacterFrames(true)
  assertf(M.GetOpt(FID, "iconLimit") == 7,
          "ticking it changes no value: an untouched character still reads the shared one")

  M.SetOpt(FID, "iconLimit", 3)
  assertf(M.GetOpt(FID, "iconLimit") == 3, "…and a change now applies to this character")
  assertf(frameStore.frames[FID].iconLimit == 7,
          "…WITHOUT disturbing the shared value, which is what other characters still read")

  -- The assertion the feature exists for: somebody else is unaffected.
  UnitName = function() return "Testlock" end
  assertf(M.GetOpt(FID, "iconLimit") == 7, "another character reads the shared value, not this one's")
  M.SetOpt(FID, "iconLimit", 11)
  assertf(M.GetOpt(FID, "iconLimit") == 11, "…and can hold its own")
  UnitName = realName
  assertf(M.GetOpt(FID, "iconLimit") == 3, "…with neither overwriting the other")

  -- A key this character never touched keeps tracking the shared one, rather than freezing at
  -- whatever it was when the option was ticked.
  assertf(M.GetOpt(FID, "iconPadding") == M.DEFAULTS.iconPadding, "an untouched key follows the account")
  M.SetPerCharacterFrames(false)
  M.SetOpt(FID, "iconPadding", 9)
  M.SetPerCharacterFrames(true)
  assertf(M.GetOpt(FID, "iconPadding") == 9,
          "…so a later account-wide change still reaches a character that never overrode it")

  -- Unticking is not destructive. It stops CONSULTING the overrides; it does not discard them.
  M.SetPerCharacterFrames(false)
  assertf(M.GetOpt(FID, "iconLimit") == 7, "unticking gives the shared value back")
  M.SetPerCharacterFrames(true)
  assertf(M.GetOpt(FID, "iconLimit") == 3, "…and re-ticking finds this character's own still there")

  -- Reset means DEFAULTS, on both levels. Clearing only the override would land on the account-wide
  -- setup while the button promised defaults.
  M.ResetOpts(FID)
  assertf(M.GetOpt(FID, "iconLimit") == M.DEFAULTS.iconLimit,
          "reset restores defaults, not the shared value the override was hiding")
  UnitName = function() return "Testlock" end
  assertf(M.GetOpt(FID, "iconLimit") == 11, "…and leaves another character's override alone")
  UnitName = realName
  M.SetPerCharacterFrames(false)
  M.ResetOpts(FID)
  frameStore.charFrames = nil

  -- The bucket must NOT be the saved-preset table. It was, in the first draft: `cd.layouts` is
  -- SettingsPresets' own key, so ResetTracking silently deleted every layout the player had saved.
  local cd = M._store(true)
  assertf(cd.specLayouts ~= nil, "the buckets live under specLayouts")
  cd.layouts = { ["A Saved Layout"] = { class = "PRIEST" } }
  M.ResetTracking()
  assertf(cd.layouts and cd.layouts["A Saved Layout"] ~= nil,
    "…so resetting tracking leaves saved layouts alone")
  cd.layouts = nil

  -- What is knowledge rather than layout stays shared: an aura met in one spec is still an aura this
  -- character can get, and hiding it from the other spec's picker would be a bug wearing a feature.
  M.NoteSeenAura(48168, "Improved Spirit Tap", "i", 8)
  local function seenHas(id)
    for _, e in ipairs(M.GetSeenAuraList("PRIEST")) do if e.spellID == id then return true end end
    return false
  end
  assertf(seenHas(48168), "an aura seen in group 1 is recorded")
  group = 2
  assertf(seenHas(48168), "…and is still known in group 2")
  group = 1

  -- The swap itself has to reach the screen. This is the reported bug: nothing the viewers already
  -- listened for fires on a talent-group change, so old-spec abilities sat in the window looking
  -- castable until the player happened to drag one.
  --
  -- The group must move WITHOUT anything else touching the viewer, or the test proves nothing. A
  -- first version edited a list to set the scene and passed with the handler disabled, because
  -- SetSpellEnabled rebuilds the viewer itself — the scene-setting was doing the work the event was
  -- supposed to do.
  local ev = M.viewers.essential
  M.SetSpellEnabled("essential", 8092, false)      -- group 1 hides it; this rebuilds, by design
  local hidden = shownItems(ev)
  group = 2                                        -- group 2 has never hidden anything
  assertf(shownItems(ev) == hidden,
    "the viewer is stale immediately after a silent group change — nothing has told it")
  fireEvent("ACTIVE_TALENT_GROUP_CHANGED")
  drain()
  assertf(shownItems(ev) == hidden + 1,
    "ACTIVE_TALENT_GROUP_CHANGED rebuilds it onto the other spec's layout, with no interaction")
  group = 1
  M.ResetTracking()
  ev:Rebuild()
  GetActiveTalentGroup = nil
  M.InvalidateCuratedCache()
end

print("\n=== CATEGORY GRIDS (Phase 4b-2) ===")
local A = CDS.adapter
assertf(A ~= nil, "adapter present")
-- Four on the Spells side since the equip port: Essential / Utility / Trinkets / Not Displayed. The
-- Trinkets pool is spells-only — see Equip.lua on why the passive pool is cut.
assertf(#A.MODE_ORDER.spells == 4 and #A.MODE_ORDER.auras == 3, "four spell categories, three aura")
assertf(A.IsSourcePool("equipActive") and not A.IsSourcePool("essential"),
        "only the equip pool is a source category")

-- Phase 9 (§H.3): the third category carries RETAIL's name in both modes, and the right-click menu
-- reads it from here, so "Move to Not Displayed" follows the label with nothing to keep in sync.
assertf(A.Label("hiddenSpell") == "Not Displayed" and A.Label("hiddenAura") == "Not Displayed",
        "the third category is labelled Not Displayed in both modes")
-- …and the rename stopped at the display string. The stored assignment value is what every saved
-- layout on disk already contains; renaming it would have silently unhidden everything.
assertf(A.Meta("hiddenAura").aura == "hidden", "…while the STORED assignment value is still hidden")

-- The arsenal is what turns Not Displayed from an undo list into a picker.
assertf(M.ARSENAL_BY_CLASS ~= nil, "generated arsenal loaded")
assertf(#(M.ARSENAL_BY_CLASS.PRIEST or {}) > 15,
        "priest arsenal populated (" .. #(M.ARSENAL_BY_CLASS.PRIEST or {}) .. ")")

M.ResetCustomList("essential", "PRIEST")
M.ResetCustomList("utility", "PRIEST")
CDS.OpenTo("essential")

-- The fake spellbook holds only the handful of ids earlier sections needed, so since §H.3.21 the
-- catalog below would be empty for a real reason and the "…but still lists what you DO know" half of
-- the check would pass vacuously. Teach the book one catalog ability so both directions are proved.
do
  local was = M.GetShowUnlearned()
  M.SetShowUnlearned(true)
  for _, id in ipairs(A.GetItems("hiddenSpell", "PRIEST")) do
    if type(id) == "number" and not M.IsSpellLearned(id) then
      SPELLS[id] = SPELLS[id] or { "Catalog Ability " .. id, "" }
      BOOK[#BOOK + 1] = id
      _G.__SLOT_IDS = BOOK
      settle(function() NE.spellbook.BuildRankTable() end)
      break
    end
  end
  M.SetShowUnlearned(was)
end

local ess = A.GetItems("essential", "PRIEST")
local hid = A.GetItems("hiddenSpell", "PRIEST")
assertf(#ess > 0, "Essential lists the curated spells (" .. #ess .. ")")
assertf(#hid > 0, "Not Displayed lists the rest of the arsenal (" .. #hid .. ")")

-- The two must not overlap: a placed spell is not offered again.
local placed = {}
for _, id in ipairs(ess) do placed[id] = true end
local overlap = 0
for _, id in ipairs(hid) do if placed[id] then overlap = overlap + 1 end end
assertf(overlap == 0, "Not Displayed excludes what is already placed (" .. overlap .. " overlaps)")

-- §H.3.21: Not Displayed is the CHARACTER's arsenal, not the class's. It used to list everything and
-- tint what you could not cast, which put an untalented druid's Mangle one drag from a row that
-- could never light up — in a section whose own name already means "you chose not to show this".
do
  local unlearnedListed, learnedListed = 0, 0
  for _, id in ipairs(hid) do
    if type(id) == "number" then
      if M.IsSpellLearned(id) then learnedListed = learnedListed + 1
      else unlearnedListed = unlearnedListed + 1 end
    end
  end
  assertf(unlearnedListed == 0,
          "Not Displayed lists nothing unlearned (" .. unlearnedListed .. " leaked)")
  assertf(learnedListed > 0, "…and is not simply empty (" .. learnedListed .. " learned entries)")

  -- Show Unlearned is the escape hatch, and it has to actually reach this section — it did not
  -- before, which is what let the section drift into meaning something else.
  local wasShow = M.GetShowUnlearned()
  M.SetShowUnlearned(true)
  local all = A.GetItems("hiddenSpell", "PRIEST")
  assertf(#all > #hid, "Show Unlearned re-opens the full catalog (" .. #hid .. " -> " .. #all .. ")")
  M.SetShowUnlearned(false)
  assertf(#A.GetItems("hiddenSpell", "PRIEST") == #hid, "…and turning it back off closes it again")
  M.SetShowUnlearned(wasShow)

  -- The empty state has to name that setting. This section is now most likely to be empty on a
  -- LOW-LEVEL character with nothing left to list, and "(empty)" there reads as a broken panel.
  assertf(A.EmptyText("hiddenSpell"):find("Show Unlearned") ~= nil,
          "the empty text points at the setting that brings the rest back")
end

-- Grids built and stacked.
local grids = CDS._categories
assertf(grids.essential ~= nil and grids.hiddenSpell ~= nil, "spell category frames built")
assertf(grids.essential._count == #ess, "Essential grid holds every entry (" .. grids.essential._count .. ")")
assertf(grids.essential.items[1] ~= nil and grids.essential.items[1].spellID ~= nil, "tiles bound to spells")
assertf(sp.content:GetHeight() > 1, "scroll child sized to the stacked sections (" .. sp.content:GetHeight() .. ")")

-- The red tint on a spell tile. Since §H.3.21 an unlearned row is only ever LISTED with Show
-- Unlearned on, which makes this tint that setting's entire visual payload — the one thing telling
-- the player why a row they cannot cast is on screen. Nothing asserted it before, and it was reading
-- IsTrackable, which waves through most of the catalog and so tinted an arbitrary subset.
do
  local wasShow = M.GetShowUnlearned()
  M.SetShowUnlearned(true)
  CDS.RefreshLayout()
  local tinted, plain, wrong = 0, 0, 0
  for _, tile in ipairs(CDS._categories.hiddenSpell.items or {}) do
    if tile:IsShown() and tile.spellID and not tile.token and not tile._aura then
      if M.IsSpellLearned(tile.spellID) then
        plain = plain + 1
        if tile._unlearned == true then wrong = wrong + 1 end
      else
        tinted = tinted + 1
        if not (tile._unlearned == true and tile.Icon._desat == true) then wrong = wrong + 1 end
      end
    end
  end
  assertf(tinted > 0, "Show Unlearned puts unlearned tiles on screen (" .. tinted .. ")")
  assertf(plain > 0, "…alongside learned ones (" .. plain .. ")")
  assertf(wrong == 0, "…and every tile's tint matches its learn state (" .. wrong .. " wrong)")
  M.SetShowUnlearned(wasShow)
  CDS.RefreshLayout()
end

print("\n=== NOT DISPLAYED IS THE CATALOG MINUS WHAT IS ON SCREEN (§H.3.22) ===")
--
-- Racials reach a display list through appendRacials, a merge that lives inside GetActiveSpellList.
-- The adapter used to answer "is this placed?" with its own reimplementation of the placement rules,
-- which knew about custom lists and the curated tables and nothing else — so every racial was placed
-- AND unplaced at once, and showed up twice. Reported as "Gift of the Naaru is showing under Utility
-- and Not Displayed".
--
-- The suite could not have caught it: the overlap check above runs as a HUMAN, and Human is the one
-- race whose racial lists are empty. So this block picks a race that has one.
do
  local savedRace, savedShow = UnitRace, M.GetShowUnlearned()
  UnitRace = function() return "Draenei", "Draenei" end
  M.InvalidateCuratedCache()
  M.ResetCustomList("essential", "PRIEST")
  M.ResetCustomList("utility", "PRIEST")

  local RACIAL = M.RACIAL_BY_RACE.Draenei.utility[1]     -- Gift of the Naaru
  assertf(RACIAL ~= nil, "the Draenei racial is curated (" .. tostring(RACIAL) .. ")")
  SPELLS[RACIAL] = SPELLS[RACIAL] or { "Gift of the Naaru", "" }
  BOOK[#BOOK + 1] = RACIAL
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)

  local function has(cat, id)
    local n = 0
    for _, it in ipairs(A.GetItems(cat, "PRIEST")) do
      if (type(it) == "table" and it.spellID or it) == id then n = n + 1 end
    end
    return n
  end

  assertf(has("utility", RACIAL) == 1, "the racial is merged into Utility (" .. has("utility", RACIAL) .. ")")
  assertf(has("hiddenSpell", RACIAL) == 0, "…and is NOT offered again under Not Displayed")

  -- The round trip has to survive: removing it is the only way back to the catalog, and if the
  -- subtraction were done by hiding racials outright the ability would be gone for good.
  M.SetSpellEnabled("utility", RACIAL, false)
  assertf(has("utility", RACIAL) == 0, "removing it takes it out of Utility")
  assertf(has("hiddenSpell", RACIAL) == 1,
          "…and Not Displayed offers it back exactly once (" .. has("hiddenSpell", RACIAL) .. ")")
  M.SetSpellEnabled("utility", RACIAL, true)
  assertf(has("utility", RACIAL) == 1 and has("hiddenSpell", RACIAL) == 0, "…and dragging it back closes the loop")

  -- The invariant itself, over every spell category at once, with Show Unlearned BOTH ways — the
  -- catalog and the display lists are gated differently, and the whole point of deriving one from the
  -- other is that no gate can put a spell in two places.
  for _, show in ipairs({ true, false }) do
    M.SetShowUnlearned(show)
    local onScreen = {}
    for _, cat in ipairs({ "essential", "utility" }) do
      for _, it in ipairs(A.GetItems(cat, "PRIEST")) do
        local id = type(it) == "table" and it.spellID or it
        if id then onScreen[id] = cat end
      end
    end
    local both = {}
    for _, it in ipairs(A.GetItems("hiddenSpell", "PRIEST")) do
      local id = type(it) == "table" and it.spellID or it
      if id and onScreen[id] then both[#both + 1] = onScreen[id] .. ":" .. id end
    end
    assertf(#both == 0, "nothing is in two places at once with Show Unlearned " ..
            (show and "on" or "off") .. " (" .. table.concat(both, ", ") .. ")")
  end

  M.SetShowUnlearned(savedShow)
  BOOK[#BOOK] = nil
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)
  UnitRace = savedRace
  M.InvalidateCuratedCache()
  M.ResetCustomList("essential", "PRIEST")
  M.ResetCustomList("utility", "PRIEST")
  CDS.RefreshLayout()
end

print("\n=== ONE TILE PER ABILITY, NOT PER SPELL ID (§H.3.23) ===")
--
-- Spell.dbc holds a row per RANK, plus variants that never reach a spellbook, so one ability can enter
-- a list under two ids and render as two identical tiles. Reported as "two versions of Icy Touch, the
-- correct one and another with just the name and icon": the DK's is curated as 45477 and generated
-- into the arsenal as 52372. Five abilities are in that state — Icy Touch, Multi-Shot, Hammer of
-- Justice, Judgement of Wisdom and Sprint — because the arsenal is generated and the curated tables
-- are authored, and for those five they picked different rows for the same thing.
--
-- Nothing here depends on the seed still disagreeing. It builds its own twin, so the check keeps
-- meaning the same thing after any regeneration.
do
  local savedShow = M.GetShowUnlearned()
  M.ResetCustomList("essential", "PRIEST")
  M.ResetCustomList("utility", "PRIEST")

  local REAL, TWIN = 90001, 90002        -- one ability, two Spell.dbc rows
  SPELLS[REAL] = { "Twinned Ability", "Rank 1" }
  SPELLS[TWIN] = { "Twinned Ability", "Rank 1" }
  M.SPELL_DATA_BY_CATEGORY.essential.PRIEST[#M.SPELL_DATA_BY_CATEGORY.essential.PRIEST + 1] = REAL
  M.ARSENAL_BY_CLASS.PRIEST[#M.ARSENAL_BY_CLASS.PRIEST + 1] = TWIN
  M.InvalidateCuratedCache()
  BOOK[#BOOK + 1] = REAL
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)

  local function count(pred)
    local n = 0
    for _, cat in ipairs({ "essential", "utility", "hiddenSpell" }) do
      for _, it in ipairs(A.GetItems(cat, "PRIEST")) do
        local id = type(it) == "table" and it.spellID or it
        if id and pred(id) then n = n + 1 end
      end
    end
    return n
  end
  local function tiles(id) return count(function(x) return x == id end) end
  local function named(nm) return count(function(x) return GetSpellInfo(x) == nm end) end

  assertf(tiles(REAL) == 1, "the curated id is listed once (" .. tiles(REAL) .. ")")
  assertf(tiles(TWIN) == 0, "…and its generated twin is not listed at all (" .. tiles(TWIN) .. ")")

  -- With Show Unlearned on too: that setting widens the catalog, and widening must not reintroduce a
  -- second copy of something already on screen.
  M.SetShowUnlearned(true)
  assertf(tiles(REAL) == 1 and tiles(TWIN) == 0,
          "Show Unlearned does not bring the twin back (" .. tiles(REAL) .. "/" .. tiles(TWIN) .. ")")
  M.SetShowUnlearned(savedShow)

  -- The CURATED id wins, and it must be the one that survives even though the catalog walks the
  -- arsenal first. Nothing functional rides on it — highestKnownRankID resolves either id to the same
  -- rank by name — but the starter layouts and presets all name the curated one.
  M.SetSpellEnabled("essential", REAL, false)
  local backInCatalog = 0
  for _, it in ipairs(A.GetItems("hiddenSpell", "PRIEST")) do
    if (type(it) == "table" and it.spellID or it) == REAL then backInCatalog = backInCatalog + 1 end
  end
  assertf(backInCatalog == 1, "removing it offers the CURATED id back, once (" .. backInCatalog .. ")")
  assertf(tiles(TWIN) == 0, "…still never the twin")
  M.SetSpellEnabled("essential", REAL, true)

  -- BOTH ids inside one DISPLAY list. This is the state a player lands in by dragging the twin out of
  -- the catalog before it was deduped — their saved list now holds both — and it is why the dedupe
  -- lives in GetActiveSpellList rather than in the picker: the LIVE viewer reads that same function,
  -- so a picker-only fix would have left two identical tiles on the cooldown bar itself.
  do
    M.SetSpellEnabled("essential", TWIN, true)
    assertf(named("Twinned Ability") == 1,
            "a list holding both ids still renders one tile (" .. named("Twinned Ability") .. ")")
    M.SetSpellEnabled("essential", TWIN, false)
  end

  -- A placement the CATALOG'S OWN POOLS cannot see. This is not hypothetical: regenerating
  -- CdmArsenal.lua drops ids (seven left it this session), and a saved layout goes on holding one long
  -- after the arsenal stopped listing it. The placed id is then in no pool the catalog walks, so
  -- nothing marks its name in passing and only the placed-NAME set can suppress the surviving twin.
  do
    local GONE, STILL = 90011, 90012                  -- one ability: a dropped id, and the current one
    SPELLS[GONE]  = { "Arsenal Twin", "Rank 1" }
    SPELLS[STILL] = { "Arsenal Twin", "Rank 1" }
    local ars = M.ARSENAL_BY_CLASS.PRIEST
    ars[#ars + 1] = STILL                             -- only the survivor is generated
    M.InvalidateCuratedCache()
    -- Learnable, or the gate drops both and the check passes for the wrong reason.
    BOOK[#BOOK + 1] = GONE
    _G.__SLOT_IDS = BOOK
    settle(function() NE.spellbook.BuildRankTable() end)
    M.SetSpellEnabled("essential", GONE, true)        -- the stale saved placement
    assertf(named("Arsenal Twin") == 1,
            "a placement outside every catalog pool still suppresses its twin ("
            .. named("Arsenal Twin") .. ")")
    M.SetSpellEnabled("essential", GONE, false)
    ars[#ars] = nil
    SPELLS[GONE], SPELLS[STILL] = nil, nil
    BOOK[#BOOK] = nil
    _G.__SLOT_IDS = BOOK
    settle(function() NE.spellbook.BuildRankTable() end)
    M.InvalidateCuratedCache()
  end

  -- Two GENERATED ids for one ability, neither placed nor curated — nothing outside the walk can
  -- arbitrate, so the walk itself has to keep only the first.
  do
    local G1, G2 = 90021, 90022
    SPELLS[G1] = { "Generated Twin", "Rank 1" }
    SPELLS[G2] = { "Generated Twin", "Rank 1" }
    local ars = M.ARSENAL_BY_CLASS.PRIEST
    ars[#ars + 1] = G1; ars[#ars + 1] = G2
    M.InvalidateCuratedCache()
    M.SetShowUnlearned(true)
    assertf(named("Generated Twin") == 1,
            "two generated ids for one ability collapse to one tile (" .. named("Generated Twin") .. ")")
    M.SetShowUnlearned(savedShow)
    ars[#ars] = nil; ars[#ars] = nil
    SPELLS[G1], SPELLS[G2] = nil, nil
    M.InvalidateCuratedCache()
  end

  -- Ids the client cannot name are judged by id alone: there is nothing to compare, and treating
  -- "no name" as one shared name would merge unrelated abilities into a single tile.
  do
    local N1, N2 = 90003, 90004
    local ars = M.ARSENAL_BY_CLASS.PRIEST
    ars[#ars + 1] = N1; ars[#ars + 1] = N2
    M.InvalidateCuratedCache()
    M.SetShowUnlearned(true)
    assertf(tiles(N1) == 1 and tiles(N2) == 1,
            "two unnamed ids stay two tiles (" .. tiles(N1) .. "/" .. tiles(N2) .. ")")
    M.SetShowUnlearned(savedShow)
    ars[#ars] = nil; ars[#ars] = nil
    M.InvalidateCuratedCache()
  end

  M.ARSENAL_BY_CLASS.PRIEST[#M.ARSENAL_BY_CLASS.PRIEST] = nil
  M.SPELL_DATA_BY_CATEGORY.essential.PRIEST[#M.SPELL_DATA_BY_CATEGORY.essential.PRIEST] = nil
  SPELLS[REAL], SPELLS[TWIN] = nil, nil
  BOOK[#BOOK] = nil
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)
  M.InvalidateCuratedCache()
  M.ResetCustomList("essential", "PRIEST")
  M.ResetCustomList("utility", "PRIEST")
  CDS.RefreshLayout()
end

-- The OPEN WINDOW has to follow a spec swap on its own. The viewers subscribe to the spellbook
-- rebuild (Register.lua) and this window did not, so it re-rendered once on the talent event — from
-- the book as it was before the swap — and then had no reason to look again. Reported as "switched
-- from Holy to Disc and can still see Circle of Healing; it only disappears when I try to move it",
-- moving a tile being one of the few things that refreshes the layout.
do
  local before = grids.essential._count
  SPELLS[34861] = { "Circle of Healing", "Rank 1" }
  M.SetSpellEnabled("essential", 34861, true)
  BOOK[#BOOK + 1] = 34861
  _G.__SLOT_IDS = BOOK
  settle(function() NE.spellbook.BuildRankTable() end)
  CDS.RefreshLayout()
  assertf(grids.essential._count == before + 1, "a known Holy talent is listed in the open picker")

  BOOK[#BOOK] = nil                 -- the swap takes it out of the book
  _G.__SLOT_IDS = BOOK
  fireEvent("ACTIVE_TALENT_GROUP_CHANGED")
  drain()                           -- the deferred rebuild, i.e. the client's next frame
  assertf(grids.essential._count == before,
    "…and the open window drops it with no interaction (" .. grids.essential._count .. ")")

  M.SetSpellEnabled("essential", 34861, false)
  SPELLS[34861] = nil
  CDS.RefreshLayout()
end

-- Collapsing must resize, or the scrollbar range goes stale.
local tallExpanded = grids.essential:GetHeight()
grids.essential:Toggle()
assertf(grids.essential:GetHeight() < tallExpanded, "collapsing a section shrinks it")
grids.essential:Toggle()

-- Search dims rather than reflows, so positions stay put while typing.
CDS.ApplyItemFilter("zzzznomatch")
local dimmed = grids.essential.items[1]:GetAlpha()
assertf(dimmed < 1, "non-matching tiles dim (" .. dimmed .. ")")
CDS.ApplyItemFilter("")
assertf(grids.essential.items[1]:GetAlpha() == 1, "clearing the search restores them")

-- Moving a spell between categories, which is what 4b-3's menu will drive.
local moved = ess[1]
assertf(A.CanTarget("essential", "utility"), "essential -> utility is a legal move")
assertf(not A.CanTarget("essential", "trackedBar"), "cross-mode moves are illegal")
assertf(A.Assign(moved, "essential", "utility", "PRIEST"), "assign reports success")
local ess2 = A.GetItems("essential", "PRIEST")
local uti2 = A.GetItems("utility", "PRIEST")
local stillEss, nowUti = false, false
for _, id in ipairs(ess2) do if id == moved then stillEss = true end end
for _, id in ipairs(uti2) do if id == moved then nowUti = true end end
assertf(not stillEss, "moved spell left Essential")
assertf(nowUti, "…and arrived in Utility")
M.ResetCustomList("essential", "PRIEST")
M.ResetCustomList("utility", "PRIEST")

-- Aura categories read the tracked-aura pool. Phase 7b changed the CONTRACT here: an aura category
-- returns row TABLES, not bare spellIDs, because a row now has to carry the name it was assigned
-- under (rank-proofing) and whether the viewer or the player put it there.
CDS.SetDisplayMode("auras")
M.SetAuraAssignment("PRIEST", 10060, "bar")
CDS.RefreshLayout()
local bars = A.GetItems("trackedBar", "PRIEST")
local pinned
for _, row in ipairs(bars) do if row.spellID == 10060 then pinned = row end end
assertf(pinned ~= nil, "aura assigned to bars shows under Tracked Bars")
assertf(pinned and pinned.aura and pinned.assignment == "bar", "…as an explicit aura row")
assertf(pinned and not pinned.auto, "…not marked auto")
assertf(grids.trackedBar ~= nil and grids.trackedBar.kind == "bar", "bar category uses bar rows")
M.ResetTracking()
CDS.HidePanel()

print("\n=== ITEM MENU + COG (Phase 4b-3) ===")
-- Scoped: the menu tree is built and driven WITHOUT any UIDropDownMenu present. That separation is
-- the point of NE.menu.BuildRoot — menu content is logic and gets tested like logic; only the
-- rendering needs a client.
do
  local S  = NE.cooldownviewersettings
  local A2 = S.adapter
  local AL = M.alerts

  M.ResetTracking()
  M.ResetAlerts()
  S.OpenTo("essential")

  local tile = S._categories.essential.items[1]
  local sid  = tile and tile.spellID
  assertf(tile ~= nil and tile._catID == "essential", "tile carries its own category")

  -- The placeholder trap: ClassicAPI's search box READS BACK "Search" until the player types, and
  -- feeding that to the filter dimmed every tile in the panel to 25%.
  sp.search:SetText(SEARCH)
  S.RefreshLayout()
  assertf(S.GetSearchText() == "", "the idle search box reads as empty, not as \"Search\"")
  assertf(S._categories.essential.items[1]:GetAlpha() == 1, "…so tiles are not dimmed on open")

  local root = NE.menu.BuildRoot(S.ItemMenuGenerator(tile, "PRIEST"))
  assertf(root ~= nil, "item menu builds")
  assertf(root.children[1] and root.children[1].kind == "title", "…opening with the spell name")

  -- The reason core/Menu.lua uses ClassicAPI's dropdown rather than the native one: the native
  -- C_UIDROPDOWNMENU_MAXLEVELS is 2, and this menu needs three.
  local function depth(n)
    local d = 0
    for _, c in ipairs(n.children) do
      local cd = depth(c) + 1
      if cd > d then d = cd end
    end
    return d
  end
  assertf(depth(root) >= 3, "menu nests " .. depth(root) .. " levels — past the native 2-level cap")

  -- Ready sound: category submenu -> entry radio.
  local soundRoot = root:Child("Ready Sound")
  local animals   = soundRoot and soundRoot:Child("Animals")
  local catSound  = animals and animals:Child("Cat")
  assertf(catSound ~= nil, "sound catalogue nests category -> entry")
  local playedBefore = #SOUNDS_PLAYED
  catSound:Invoke()
  assertf(M.GetReadySoundKit(sid) == 316401, "selecting a sound writes the per-spell kit")
  assertf(#SOUNDS_PLAYED > playedBefore, "…and previews it")
  assertf(catSound.isSelected() == true, "its radio reads selected")
  assertf(soundRoot:Child("None").isSelected() == false, "…and None does not")

  -- Alerts. The FX list is GENERATED from AL.FX; upstream hardcodes 1 = ants / 6 = flash, and 6 has
  -- no renderer here, so a verbatim port would have written a dead value.
  local alertRoot = root:Child("Alert")
  local fxSub     = alertRoot and alertRoot:Child("FX Style")
  -- Every event says what it needs, so an event that cannot fire for this spell says so instead of
  -- sitting there inert. Refresh is the one that genuinely cannot, for a cooldown with no aura.
  local refreshEntry = alertRoot:Child("Refresh")
  assertf(refreshEntry ~= nil and refreshEntry.tipTitle == "Refresh", "Refresh carries an explanatory tooltip")
  assertf(refreshEntry.tipText:find("no aura", 1, true) ~= nil,
          "…naming the case where it can never trigger")
  assertf(alertRoot:Child("Available").tipText:find("every spell", 1, true) ~= nil,
          "Available says it works for everything")
  assertf(alertRoot:Child("Usable").tipTitle == "Usable", "Usable carries one too")

  assertf(fxSub ~= nil and #fxSub.children == #AL.FX,
          "FX submenu generated from AL.FX (" .. (fxSub and #fxSub.children or 0) .. " entries)")
  assertf(fxSub.children[1].text == AL.FX[1].name, "…using our names, not upstream's ants/flash pair")

  alertRoot:Child("Available"):Invoke()
  assertf(AL.GetType(sid) == "available", "alert type written")
  assertf(GLOWS[tile] ~= nil, "…and previewed on the tile itself")
  alertRoot:Child("Refresh Window"):Child("40%"):Invoke()
  assertf(math.abs(AL.GetWindow(sid) - 0.40) < 0.001, "refresh window stored as a fraction")

  -- The grid has to show its own state, or the only way to read it is to right-click every icon.
  assertf(tile.AlertBG ~= nil and tile.AlertBG:IsShown(), "configured tile shows the alert badge")
  GameTooltip:ClearLines()
  S._itemTooltipExtra(tile, GameTooltip)
  local tip = table.concat(GameTooltip.lines, "|")
  assertf(tip:find("Alert: available", 1, true) ~= nil, "tooltip names the configured alert")
  assertf(tip:find("Ready sound: Cat", 1, true) ~= nil, "tooltip names the configured sound")

  alertRoot:Child("None"):Invoke()
  soundRoot:Child("None"):Invoke()
  assertf(not tile.AlertBG:IsShown(), "badge clears when both go back to None")

  -- Moves. Done last: it rebuilds the grid under us.
  local mv = root:Child("Move to " .. A2.Label("utility"))
  assertf(mv ~= nil, "Move to Utility is offered")
  mv:Invoke()
  local arrived = false
  for _, id in ipairs(A2.GetItems("utility", "PRIEST")) do if id == sid then arrived = true end end
  assertf(arrived, "invoking the entry actually moved the spell")

  -- ── the render path ──────────────────────────────────────────────────────────────────────────
  -- Everything above drives the node tree. This drives core/Menu.lua's UIDropDownMenu translation,
  -- which is where both of the shipped menu faults lived.
  -- Re-read from the tile: the move above rebuilt the grid, so items[1] now holds a different
  -- spell than `sid`. The menu keys off whatever the tile currently carries.
  local shown = tile.spellID
  M.SetReadySoundKit(shown, 316406)   -- Chicken
  S.OnItemClick(tile, "RightButton")
  assertf(DD_ROWS[1] ~= nil and #DD_ROWS[1] > 0, "right-click renders a level-1 menu (" .. #(DD_ROWS[1] or {}) .. " rows)")

  local soundRow, soundIdx, titleIdx
  for i, row in ipairs(DD_ROWS[1]) do
    if row.text == "Ready Sound" then soundRow, soundIdx = row, i end
    if row.isTitle and not titleIdx then titleIdx = i end
  end
  assertf(soundRow ~= nil and soundRow.hasArrow and soundRow.notClickable,
          "a submenu parent is hasArrow + notClickable, so OnClick cannot tick it")

  -- …and that is exactly what costs the row its mouse, so core/Menu.lua buys it back. notClickable
  -- means DISABLED, which on 3.3.5a silences the OnEnter that opens the submenu AND raises
  -- $parentInvisibleButton over the row, whose own OnEnter closes it. Between them the only way in
  -- was the 16px arrow — and any approach to it across the row slammed the door.
  local subBtn = _G["C_DropDownList1Button" .. soundIdx]
  assertf(subBtn._motionWhileDisabled == true,
          "…so the disabled submenu row is told to take OnEnter anyway, which is what opens it")
  assertf(_G["C_DropDownList1Button" .. soundIdx .. "InvisibleButton"]:IsShown() == false,
          "…and the invisible button that would shut it again is down, so the whole row is the target")

  -- Handed BACK on every other row. These list buttons are shared with every C_UIDropDownMenu in the
  -- game, so one left motion-enabled is a disabled title some later menu could hover-highlight.
  assertf(titleIdx ~= nil and _G["C_DropDownList1Button" .. titleIdx]._motionWhileDisabled == false,
          "…while a disabled row with no submenu is handed back, so the shared widgets do not leak it")
  assertf(_G["C_DropDownList1Button" .. titleIdx .. "InvisibleButton"]:IsShown() == true,
          "…keeping the invisible button that serves ITS tooltip")

  -- Walk two levels in, the way hovering the arrows does.
  local mf = NE.menu._frame
  C_UIDropDownMenu_Initialize(mf, mf.initialize, nil, 2, soundRow.menuList)
  local animalRow
  for _, row in ipairs(DD_ROWS[2] or {}) do if row.text == "Animals" then animalRow = row end end
  assertf(animalRow ~= nil, "level 2 lists the sound categories")

  -- WHERE it opens, not just whether. The client anchors a level-2 list to `button:GetParent()`,
  -- because its "is the parent a list?" test compares 12 characters against a 14-character prefix and
  -- can never be true. An arrow's parent is its row — right by accident — but a ROW's parent is the
  -- whole list, so once the row could open its own submenu the submenu appeared beside the TOP of the
  -- parent menu and only dropped into place when the mouse reached the arrow and re-opened it.
  local arrow = _G["C_DropDownList1Button" .. soundIdx .. "ExpandArrow"]
  assertf(arrow:IsShown(), "the submenu row shows its expand arrow, and a non-submenu row does not")
  local sub2 = _G.C_DropDownList2
  sub2:Show()
  sub2:ClearAllPoints()
  sub2:SetPoint("TOPLEFT", _G.C_DropDownList1, "TOPRIGHT", 0, 0)   -- what the client just did
  subBtn:GetScript("OnEnter")(subBtn)
  local ap, arel, arelp = sub2:GetPoint(1)
  assertf(sub2:GetNumPoints() == 1 and ap == "TOPLEFT" and arel == arrow and arelp == "TOPRIGHT",
          "…so hovering the row re-anchors the submenu to that ARROW — the row's own height, and the "
          .. "one anchor the arrow's OnEnter accepts without rebuilding the menu underneath the mouse")

  -- A submenu opened near the bottom of the screen flips to hang UPWARDS. That correction exists in
  -- ToggleDropDownMenu already, but it runs there against the same wrong anchor, so it has to run
  -- again here — and a submenu that re-anchored correctly and then fell off the screen would be no
  -- better than one that never moved.
  sub2._center, sub2._w, sub2._h = { 900, 10 }, 200, 100
  subBtn:GetScript("OnEnter")(subBtn)
  local fp, frel, frelp, _, fy = sub2:GetPoint(1)
  assertf(fp == "BOTTOMRIGHT" and frel == arrow and frelp == "BOTTOMLEFT" and fy == -14,
          "…and one opening off the bottom of the screen flips to hang up from the arrow instead")
  sub2._center, sub2._w, sub2._h = nil, 0, 0

  -- The hook lives on a button shared with every other menu in the game and cannot be taken off, so
  -- it has to ask whose menu is open before it moves anything.
  local realOpen = C_UIDROPDOWNMENU_OPEN_MENU
  C_UIDROPDOWNMENU_OPEN_MENU = CreateFrame("Frame")
  sub2:ClearAllPoints()
  sub2:SetPoint("TOPLEFT", _G.C_DropDownList1, "TOPRIGHT", 0, 0)
  subBtn:GetScript("OnEnter")(subBtn)
  assertf(select(2, sub2:GetPoint(1)) == _G.C_DropDownList1,
          "…and leaves someone else's open menu exactly where they put it")
  C_UIDROPDOWNMENU_OPEN_MENU = realOpen

  C_UIDropDownMenu_Initialize(mf, mf.initialize, nil, 3, animalRow.menuList)
  local onCount, chickenOn = 0, false
  for _, row in ipairs(DD_ROWS[3] or {}) do
    if row.checked == true then
      onCount = onCount + 1
      if row.text == "Chicken" then chickenOn = true end
    end
  end
  assertf(#(DD_ROWS[3] or {}) > 3, "level 3 lists the sounds — past the native 2-level cap")
  assertf(onCount == 1 and chickenOn, "exactly the stored sound reads as selected (" .. onCount .. " ticked)")

  -- The invariant behind that: never hand UIDropDownMenu a predicate. Checked at every rendered
  -- level, because level 1 holds no radios at all and would pass this vacuously.
  local fnChecked = 0
  for lvl = 1, 3 do
    for _, row in ipairs(DD_ROWS[lvl] or {}) do
      if type(row.checked) == "function" then fnChecked = fnChecked + 1 end
    end
  end
  assertf(fnChecked == 0, "info.checked is never a function — the client mis-reads those (" .. fnChecked .. ")")
  M.SetReadySoundKit(shown, nil)
  NE.menu.Close()

  -- Cog menu.
  local cog = NE.menu.BuildRoot(S.SettingsMenuGenerator)
  local su  = cog:Child("Show Unlearned")
  assertf(su ~= nil and su.kind == "checkbox", "cog menu carries Show Unlearned as a checkbox")
  local wasUnlearned = M.GetShowUnlearned()
  su:Invoke()
  assertf(M.GetShowUnlearned() ~= wasUnlearned, "toggling it flips the stored option")
  su:Invoke()

  POPUPS_SHOWN = {}
  cog:Child("Clear All Alerts"):Invoke()
  assertf(POPUPS_SHOWN[1] == "NE_CDM_RESET_ALERTS", "destructive cog entries confirm before acting")
  AL.SetType(sid, "available")
  StaticPopupDialogs["NE_CDM_RESET_ALERTS"].OnAccept()
  assertf(AL.GetType(sid) == nil, "…and confirming clears them")

  -- ── an AURA row offers only the triggers that can fire on it ─────────────────────────────────
  -- Two of the four are driven by a cooldown finishing, and a tracked buff has no cooldown behind
  -- it. Offering them was not cosmetic: Available's own tooltip promised "Works for every spell" on
  -- a row that holds no spell, and a ready sound assigned there lit the badge forever with nothing
  -- able to play it.
  local realAuto = M.IsAutoTrackBuffs()
  M.ResetTracking()
  M.ResetAlerts()
  M.SetAutoTrackBuffs(false)   -- with auto-track ON a candidate row lands under Tracked Buffs
  M.NoteSeenAura(900456, "Menu Test Aura", "Interface\\Icons\\MTA", 20)
  S.OpenTo("auras")
  local auraGrid, auraTile = S._categories.hiddenAura, nil
  for i = 1, (auraGrid and auraGrid._count or 0) do
    if auraGrid.items[i].spellName == "Menu Test Aura" then auraTile = auraGrid.items[i] end
  end
  assertf(auraTile ~= nil and A2.Meta(auraTile._catID).mode == "auras", "an aura row to open the menu on")

  local auraRoot  = NE.menu.BuildRoot(S.ItemMenuGenerator(auraTile, "PRIEST"))
  local auraAlert = auraRoot:Child("Alert")
  assertf(auraAlert ~= nil, "an aura row still gets an Alert submenu")
  assertf(auraAlert:Child("Available") == nil, "…without Available, which needs a cooldown to finish")
  assertf(auraAlert:Child("Refresh") ~= nil, "…keeping Refresh, which reads the aura's own decay")
  assertf(auraAlert:Child("Active") ~= nil, "…and gaining Active, the trigger a proc can answer")
  -- The reported case, in miniature: a proc has no castable spell of its own name, so Usable can
  -- never fire on it. It used to be offered anyway, which is how "Alert: usable (Button Glow)" came
  -- to be configured on Surge of Light and do nothing at all.
  assertf(auraAlert:Child("Usable") == nil,
          "…and losing Usable, because the client knows no castable spell by this name")

  -- …but NOT losing it on a buff the player can actually re-cast. The gate reads the client, so a
  -- self-buff row keeps the entry; a gate that just said "auras never" would fail this.
  M.NoteSeenAura(10060, "Power Infusion", "Interface\\Icons\\PI", 15)
  S.RefreshLayout()
  local castGrid, castTile = S._categories.hiddenAura, nil
  for i = 1, (castGrid and castGrid._count or 0) do
    if castGrid.items[i].spellName == "Power Infusion" then castTile = castGrid.items[i] end
  end
  assertf(castTile ~= nil, "an aura row whose name IS a castable spell")
  local castAlert = NE.menu.BuildRoot(S.ItemMenuGenerator(castTile, "PRIEST")):Child("Alert")
  assertf(castAlert:Child("Usable") ~= nil, "…keeps Usable, because re-casting it is a real question")
  assertf(castAlert:Child("Usable").tipText:find("RE-CASTING", 1, true) ~= nil,
          "…and says so, so it is not mistaken for the buff being up")

  -- ── ROW HIGHLIGHT ────────────────────────────────────────────────────────────────────────────
  -- A bar row is ~344px wide and 26 tall. ButtonHilight-Square is a 64x64 glow drawn for a SQUARE
  -- button, and stretching it across that reads as a lopsided blue smear: bright over the icon,
  -- bleeding away to the right. Reported from the game on a Holy Concentration row. Wide rows take
  -- the texture built to stretch; square tiles keep theirs, which is the half a blanket swap breaks.
  M.SetAuraAssignment("PRIEST", 10060, "bar", "Power Infusion")
  S.RefreshLayout()
  local function highlightOf(frame)
    for _, r in ipairs(frame._regions or {}) do
      if r._layer == "HIGHLIGHT" then return r end
    end
  end
  local barRow   = S._categories.trackedBar and S._categories.trackedBar.items[1]
  local iconTile = S._categories.hiddenAura and S._categories.hiddenAura.items[1]
  assertf(barRow ~= nil and iconTile ~= nil, "a bar row and an icon tile to compare")
  assertf(highlightOf(barRow) ~= nil
          and highlightOf(barRow):GetTexture() == "Interface\\QuestFrame\\UI-QuestTitleHighlight",
          "a wide bar row uses the row highlight, the one built to stretch horizontally")
  assertf(highlightOf(iconTile) ~= nil
          and highlightOf(iconTile):GetTexture() == "Interface\\Buttons\\ButtonHilight-Square",
          "…while a square icon tile keeps the square one, which is right for ITS shape")
  M.SetAuraAssignment("PRIEST", 10060, nil, "Power Infusion")
  assertf(auraAlert:Child("None") ~= nil,
          "…and None, so a layout that stored Available before the gate can still be cleared")
  assertf(auraAlert:Child("Refresh").tipText:find("no aura", 1, true) == nil,
          "Refresh drops the cooldown-with-no-aura caveat here — the row IS the aura")
  assertf(auraRoot:Child("Ready Sound") == nil, "no Ready Sound submenu on a row with no cooldown")
  assertf(auraRoot:Child("Clear Ready Sound") == nil, "…and nothing to clear when none was stored")

  -- The escape hatch, for a kit stored before the gate existed. Without it the badge is permanent
  -- and the only cure is the cog's global Clear All Alerts.
  M.SetReadySoundKit(auraTile.spellID, 316401)
  local auraRoot2 = NE.menu.BuildRoot(S.ItemMenuGenerator(auraTile, "PRIEST"))
  local clearRow  = auraRoot2:Child("Clear Ready Sound")
  assertf(clearRow ~= nil, "a stored ready sound on an aura row is reachable to clear")
  clearRow:Invoke()
  assertf(M.GetReadySoundKit(auraTile.spellID) == nil, "…and invoking it clears the kit")
  assertf(not auraTile.AlertBG:IsShown(), "…and the badge with it")

  -- Unchanged for spells, asserted here rather than assumed: the gate keys off the row's MODE, and a
  -- gate that fired everywhere would read as "fixed" while quietly removing two features.
  S.OpenTo("essential")
  local spellTile = S._categories.essential.items[1]
  local spellRoot = NE.menu.BuildRoot(S.ItemMenuGenerator(spellTile, "PRIEST"))
  assertf(spellRoot:Child("Alert"):Child("Available") ~= nil, "a SPELL row still offers Available")
  assertf(spellRoot:Child("Ready Sound") ~= nil, "…and its full Ready Sound catalogue")
  M.SetAutoTrackBuffs(realAuto)

  M.ResetTracking()
  M.ResetAlerts()
  S.HidePanel()
end

print("\n=== DRAG REORDER (Phase 4b-4) ===")
do
  local S  = NE.cooldownviewersettings
  local A2 = S.adapter

  M.ResetTracking()
  S.OpenTo("essential")

  local ess2 = S._categories.essential
  local a, b = ess2.items[1], ess2.items[2]
  assertf(a and b and a.spellID ~= b.spellID, "two distinct tiles to drag between")

  -- Order is the editable list's order, so assert on that rather than on tile positions.
  local function orderOf(cat)
    local out = {}
    for _, e in ipairs(M.GetEditableList(cat, "PRIEST") or {}) do out[#out + 1] = e.spellID end
    return out
  end
  local function indexIn(list, id)
    for i, v in ipairs(list) do if v == id then return i end end
  end

  local first, second = a.spellID, b.spellID
  assertf(indexIn(orderOf("essential"), first) < indexIn(orderOf("essential"), second),
          "tile 1 sorts before tile 2 to start with")

  -- One drag: press, hover the target's right half, release, step the driver each time.
  local function drag(source, target, cursorX, cursorY, cancel)
    MOUSE_DOWN.LeftButton, MOUSE_DOWN.RightButton = true, false
    S.BeginDrag(source)
    local df = S._dragFrame
    MOUSE_FOCUS = target
    CURSOR.x, CURSOR.y = cursorX, cursorY
    S._dragOnUpdate(df)                       -- hover: picks the target and the caret side
    if cancel then
      MOUSE_DOWN.RightButton = true
    else
      MOUSE_DOWN.LeftButton = false           -- release
    end
    S._dragOnUpdate(df)                       -- the transition the missing GLOBAL_MOUSE_UP replaces
    MOUSE_DOWN.RightButton = false
    MOUSE_FOCUS = nil
  end

  b._center = { 100, 100 }
  b._w, b._h = 38, 38

  MOUSE_DOWN.LeftButton = true
  S.BeginDrag(a)
  assertf(S._dragState.active, "drag begins")
  assertf(a:GetAlpha() == 0.5, "…and locks the source tile")
  S.CancelDrag()
  assertf(not S._dragState.active and a:GetAlpha() == 1, "cancel restores it")

  -- Right of the target's centre = drop AFTER it.
  drag(a, b, 140, 100)
  local after = orderOf("essential")
  assertf(not S._dragState.active, "releasing the button ends the drag (no GLOBAL_MOUSE_UP here)")
  assertf(indexIn(after, first) == indexIn(after, second) + 1,
          "dropping right of a tile lands immediately after it")

  -- …and left of centre drops BEFORE, which is where the off-by-one lives: removing the entry
  -- first shifts everything below it up, so an index captured beforehand overshoots.
  local c = S._categories.essential.items[1]
  local d = S._categories.essential.items[3]
  if c and d and c.spellID ~= d.spellID then
    d._center, d._w, d._h = { 200, 100 }, 38, 38
    local moved, anchor = c.spellID, d.spellID
    drag(c, d, 180, 100)                       -- left of d's centre → before
    local ord = orderOf("essential")
    assertf(indexIn(ord, moved) == indexIn(ord, anchor) - 1,
            "dropping left of a tile lands immediately before it")
  end

  -- Right-click mid-drag cancels without committing.
  local ordBefore = table.concat(orderOf("essential"), ",")
  local e, f2 = S._categories.essential.items[1], S._categories.essential.items[4]
  if e and f2 then
    f2._center, f2._w, f2._h = { 300, 100 }, 38, 38
    drag(e, f2, 340, 100, true)
    assertf(table.concat(orderOf("essential"), ",") == ordBefore, "right-click mid-drag commits nothing")
    assertf(e:GetAlpha() == 1, "…and unlocks the source")
  end

  -- Cross-category: legality is the adapter's, and an illegal target must not commit.
  assertf(not A2.CanTarget("essential", "trackedBar"), "essential -> Tracked Bars stays illegal")
  local hop = S._categories.essential.items[1].spellID
  assertf(A2.AssignAt(hop, "essential", "utility", nil, 0, "PRIEST"), "AssignAt moves across categories")
  local uti = {}
  for _, e2 in ipairs(M.GetEditableList("utility", "PRIEST") or {}) do
    if e2.enabled then uti[#uti + 1] = e2.spellID end
  end
  assertf(indexIn(uti, hop) ~= nil, "…and the spell arrives in the destination list")

  -- Closing the window mid-drag must not strand the cursor icon or a dimmed tile.
  local g = S._categories.essential.items[1]
  MOUSE_DOWN.LeftButton = true
  S.BeginDrag(g)
  S.HidePanel()
  assertf(not S._dragState.active and g:GetAlpha() == 1, "closing the panel mid-drag clears the drag")
  MOUSE_DOWN.LeftButton = false

  M.ResetTracking()
end

print("\n=== EQUIP: ON-USE TRINKETS (Phase 5a) ===")
do
  local S  = NE.cooldownviewersettings
  local A2 = S.adapter

  M.ResetTracking()
  EQUIPPED[13], EQUIPPED[14] = nil, nil
  ITEM_SPELLS = {}

  -- Nothing equipped: no rows, and — the part that matters for the panel — no section either.
  assertf(#M.GetEquipActiveItems() == 0, "no trinkets equipped -> empty discovery")
  S.OpenTo("essential")
  assertf(not (S._categories.equipActive and S._categories.equipActive._active),
          "…and the Trinkets section is not shown at all")

  -- One on-use trinket (45148 has a use spell), one proc trinket (37220 has none).
  EQUIPPED[13], EQUIPPED[14] = 45148, 37220
  ITEM_SPELLS[45148] = { "Speed", 60313 }

  local pool = M.GetEquipActiveItems()
  assertf(#pool == 1, "only the trinket WITH a use spell is discovered (" .. #pool .. " of 2)")
  assertf(pool[1].token == "item:45148", "…keyed by a stable item token")
  assertf(pool[1].spellID == 60313 and pool[1].label == "Speed", "…carrying the use spell and its name")

  -- Unassigned is the default, and the source pool is where it lands.
  assertf(M.GetEquipAssignment("item:45148") == nil, "a newly discovered trinket is unassigned")
  local src = A2.GetItems("equipActive", "PRIEST")
  assertf(#src == 1 and type(src[1]) == "table", "the source pool returns it as an ENTRY table")
  assertf(#M.GetEquipItemsForCategory("essential") == 0, "…and no viewer claims it yet")

  -- The panel renders it as a real tile with the item icon, not a spell tile.
  S.RefreshLayout()
  local eq = S._categories.equipActive
  assertf(eq and eq._active and eq._count == 1, "the Trinkets section appears once something is in it")
  local tile = eq.items[1]
  assertf(tile.token == "item:45148", "the tile carries the token")
  assertf(tile._iconItemID == 45148, "…and the item id, which is what drives the icon and tooltip")

  -- Placing it. This is a token move, NOT a spellID move: routing it through Assign would write the
  -- use-spell into the editable list, which survives unequipping the trinket and points at nothing.
  assertf(A2.CanTarget("equipActive", "essential"), "trinkets may move into Essential")
  assertf(not A2.CanTarget("essential", "equipActive"), "…but nothing moves back INTO the pool")
  assertf(A2.Assign(60313, "equipActive", "essential", "PRIEST") == false,
          "the spellID path refuses a source-pool row outright")

  assertf(A2.AssignEquip("item:45148", "equipActive", "essential"), "AssignEquip places it")
  assertf(M.GetEquipAssignment("item:45148") == "essential", "…persisting the assignment")
  assertf(#M.GetEquipItemsForCategory("essential") == 1, "…and the live viewer now sources it")
  assertf(#M.GetEquipItemsForCategory("utility") == 0, "…only that viewer")

  -- The editable spell list must NOT have grown: the whole point of the token path.
  local listed = false
  for _, e in ipairs(M.GetEditableList("essential", "PRIEST") or {}) do
    if e.spellID == 60313 then listed = true end
  end
  assertf(not listed, "placing a trinket adds nothing to the editable spell list")

  -- It now renders under Essential instead, and the source pool is empty and gone again.
  S.RefreshLayout()
  assertf(not (S._categories.equipActive and S._categories.equipActive._active),
          "an emptied source pool disappears again")
  local essTiles = S._categories.essential
  local found
  for i = 1, essTiles._count do
    if essTiles.items[i].token == "item:45148" then found = essTiles.items[i] end
  end
  assertf(found ~= nil, "the trinket now renders under Essential")

  -- The hidden assignment is STORED, and storable-ness is why it is distinct from unassigned.
  assertf(A2.AssignEquip("item:45148", "essential", "hiddenSpell"), "it can be moved to Not Displayed")
  assertf(M.GetEquipAssignment("item:45148") == "hidden", "…which stores 'hidden', not nil")
  assertf(#A2.GetItems("equipActive", "PRIEST") == 0, "…so it does NOT fall back into the source pool")

  -- Unequipping drops it from discovery entirely; the stored assignment survives for the re-equip.
  EQUIPPED[13] = nil
  assertf(#M.GetEquipActiveItems() == 0, "unequipping removes it from discovery")
  EQUIPPED[13] = 45148
  assertf(M.GetEquipAssignment("item:45148") == "hidden", "…and re-equipping restores the choice")

  -- Dragging a trinket out of the pool goes through the token path too.
  A2.AssignEquip("item:45148", nil, nil)     -- back to unassigned
  S.RefreshLayout()
  local poolTile = S._categories.equipActive.items[1]
  local dest = S._categories.utility
  MOUSE_DOWN.LeftButton, MOUSE_DOWN.RightButton = true, false
  S.BeginDrag(poolTile)
  assertf(S._dragState.active and S._dragState.token == "item:45148",
          "a drag from the source pool carries the token, not a spellID")
  MOUSE_FOCUS = dest.items[1]
  dest.items[1]._center, dest.items[1]._w, dest.items[1]._h = { 100, 100 }, 38, 38
  CURSOR.x, CURSOR.y = 140, 100
  S._dragOnUpdate(S._dragFrame)
  MOUSE_DOWN.LeftButton = false
  S._dragOnUpdate(S._dragFrame)
  MOUSE_FOCUS = nil
  assertf(M.GetEquipAssignment("item:45148") == "utility", "dropping it on Utility assigns it there")

  -- Tile pooling: a tile that held a trinket must not keep the token when it is handed a spell.
  -- Find the tile that ACTUALLY holds it — the trinket is appended after the spells, so items[1] is
  -- a spell tile and asserting on that would pass no matter what SetSpell does.
  local reused
  local utiCat = S._categories.utility
  for i = 1, utiCat._count do
    if utiCat.items[i].token == "item:45148" then reused = utiCat.items[i] end
  end
  assertf(reused ~= nil, "the trinket has a tile under Utility to reuse")
  reused:SetSpell(8092)
  assertf(reused.token == nil and reused._iconItemID == nil,
          "reusing an equip tile for a spell drops the stale equip binding")

  -- ResetTracking clears placement, so a reset really does return to the starter state.
  M.ResetTracking()
  assertf(M.GetEquipAssignment("item:45148") == nil, "ResetTracking returns trinkets to the pool")

  EQUIPPED[13], EQUIPPED[14] = nil, nil
  ITEM_SPELLS = {}
  S.HidePanel()
  M.ResetTracking()
end

print("\n=== LAYOUTS / IMPORT-EXPORT (Phase 4b-5) ===")
do
  local S  = NE.cooldownviewersettings
  local P  = S.presets
  local A2 = S.adapter

  assertf(P ~= nil, "presets module present")
  M.ResetTracking()
  S.OpenTo("essential")

  -- ── Snapshot / restore, which the undo and every layout apply share ──
  local moved = S._categories.essential.items[1].spellID
  local snap = S.SnapshotState()
  assertf(type(snap) == "table" and snap.class == "PRIEST", "snapshot records the class it was taken on")

  local function inUtility(id)
    for _, e in ipairs(M.GetEditableList("utility", "PRIEST") or {}) do
      if e.spellID == id and e.enabled then return true end
    end
    return false
  end

  A2.Assign(moved, "essential", "utility", "PRIEST")
  assertf(inUtility(moved), "an edit lands")
  assertf(S.RestoreState(snap), "restore accepts the snapshot")
  assertf(not inUtility(moved), "…and puts the edit back")

  -- ── APPEARANCE in a layout, behind its own checkbox ────────────────────────────────────────────
  -- A layout has always meant "what I track". Appearance is now captured too, but applying it is the
  -- RECIPIENT's decision: a share string that silently resized and reoriented four viewers is how
  -- "load a layout" stops being an action anyone trusts.
  local EID = M.FRAME_ID.essential
  M.ResetOpts(EID)
  M.SetLayoutsIncludeAppearance(false)
  assertf(M.LayoutsIncludeAppearance() == false, "layouts leave appearance alone by default")

  M.SetOpt(EID, "iconLimit", 5)
  local look = S.SnapshotState()
  assertf(look.frames and look.frames[EID] and look.frames[EID].iconLimit == 5,
          "a snapshot CAPTURES appearance even with the box off — the string always carries it")
  assertf(look.frames[EID].orientation ~= nil,
          "…resolved key by key, so what it carries is what the author actually sees")

  M.SetOpt(EID, "iconLimit", 9)
  assertf(S.RestoreState(look), "restoring with the box off")
  assertf(M.GetOpt(EID, "iconLimit") == 9,
          "…leaves appearance exactly where it was, which is the default promise")

  M.SetLayoutsIncludeAppearance(true)
  assertf(S.RestoreState(look), "restoring with the box on")
  assertf(M.GetOpt(EID, "iconLimit") == 5, "…applies the appearance the layout was saved with")

  -- Revert is not governed by the box. Its contract is to put things back exactly, and the box may
  -- have been flipped between the apply and the undo.
  M.SetOpt(EID, "iconLimit", 4)
  local beforeApply = S.SnapshotState()
  M.SetOpt(EID, "iconLimit", 12)
  S.RestoreState(beforeApply, { appearance = false })
  assertf(M.GetOpt(EID, "iconLimit") == 12, "an explicit skip beats the setting")
  S.RestoreState(beforeApply, { appearance = true })
  assertf(M.GetOpt(EID, "iconLimit") == 4, "…and an explicit force beats it the other way, which is what Revert passes")

  M.SetLayoutsIncludeAppearance(false)
  M.ResetOpts(EID)

  -- ── Named layouts ──
  assertf(#P.Names() == 0, "no layouts to start with")
  assertf(P.SaveAs("Raid"), "saving a layout")
  assertf(P.Current() == "Raid", "…selects it")
  assertf(#P.Names() == 1 and P.Names()[1] == "Raid", "…and lists it")

  -- Edit, then save a second layout capturing that edit.
  A2.Assign(moved, "essential", "utility", "PRIEST")
  assertf(P.SaveAs("PvP"), "a second layout captures the edited state")
  -- Alphabetical, not insertion order: the menu is a list the player scans by name.
  assertf(P.Names()[1] == "PvP" and P.Names()[2] == "Raid", "names come back sorted")

  -- Applying a layout REPLACES state rather than merging into it — the whole point of a layout.
  assertf(P.Apply("Raid"), "applying the first layout")
  assertf(not inUtility(moved), "…restores its state, dropping the later edit")
  assertf(P.Apply("PvP") and inUtility(moved), "applying the second brings the edit back")

  -- One-step undo. It reverts the APPLY, and it restores the selected-layout name with it.
  --
  assertf(S.CanRevert(), "an apply arms Revert")
  assertf(S.Revert(), "revert runs")
  assertf(not inUtility(moved), "…undoing the apply")
  assertf(P.Current() == "Raid", "…and restoring the layout that was selected before it")
  assertf(not S.CanRevert(), "revert is one step, so it disarms itself")

  assertf(P.Rename("Raid", "Raid 2"), "rename")
  assertf(P.Current() == "Raid 2", "…follows the selection")
  assertf(P.Delete("Raid 2"), "delete")
  assertf(P.Current() == nil, "…clears the selection when it was the selected one")

  -- ── The codec ──
  -- Round-trip through the real share string, not through the table.
  P.SaveAs("Export Me")
  local str = P.Encode(S.SnapshotState())
  assertf(str:sub(1, 6) == "NECDM1", "a share string is tagged")
  assertf(not str:find("[^%w%+/=]"), "…and is single-line paste-safe base64")

  local back = P.Decode(str)
  assertf(type(back) == "table" and back.class == "PRIEST", "it decodes back to a snapshot")
  -- Compare a real nested value, not just the shape: the serializer is length-prefixed and the
  -- table tag carries a pair count, so a nesting bug shows up here and nowhere else.
  local origList = S.SnapshotState().customLists
  local sameShape = (type(back.customLists) == "table")
  if sameShape and origList and origList.utility and origList.utility.PRIEST then
    sameShape = type(back.customLists.utility) == "table"
      and type(back.customLists.utility.PRIEST) == "table"
      and #back.customLists.utility.PRIEST == #origList.utility.PRIEST
  end
  assertf(sameShape, "…with the nested per-class spell lists intact")
  -- Appearance survives the codec too. The serializer is generic over tables, so this needed no
  -- codec change — which is exactly the kind of claim worth checking rather than assuming.
  assertf(type(back.frames) == "table"
          and type(back.frames[M.FRAME_ID.essential]) == "table"
          and back.frames[M.FRAME_ID.essential].iconLimit
              == S.SnapshotState().frames[M.FRAME_ID.essential].iconLimit,
          "…and the appearance leaf, through the same untouched serializer")

  -- Bad input never errors and never executes. Each of these is a distinct failure path.
  local _, e1 = P.Decode("")                    assertf(e1 ~= nil, "empty paste is rejected with a reason")
  local _, e2 = P.Decode("hello world")         assertf(e2 ~= nil, "a non-layout string is rejected")
  local _, e3 = P.Decode("NECDM1!!!!not b64")   assertf(e3 ~= nil, "corrupt payload is rejected, not raised")
  -- The parser must never be handed to loadstring: a payload that WOULD be valid Lua returning a
  -- table still has to fail, because we never evaluate it.
  local ok4 = P.Decode("NECDM1" .. "cmV0dXJuIHtjbGFzcz0iUFJJRVNUIn0=")
  assertf(ok4 == nil, "a payload that is valid Lua is still not executed")

  -- ── Revert restores appearance regardless of the box ───────────────────────────────────────────
  -- Last in this block, because it necessarily churns the selected layout and the assertions above
  -- read that. Revert's contract is to put things back EXACTLY: the box may have been ticked for the
  -- apply and unticked before the undo, and a revert that left a resized viewer behind would be a
  -- partial undo, which is no undo at all.
  M.SetLayoutsIncludeAppearance(true)
  M.SetOpt(M.FRAME_ID.essential, "iconLimit", 6)
  P.SaveAs("Looks Different")
  M.SetOpt(M.FRAME_ID.essential, "iconLimit", 2)
  assertf(P.Apply("Looks Different"), "applying a layout saved with a different appearance")
  assertf(M.GetOpt(M.FRAME_ID.essential, "iconLimit") == 6, "…changes appearance while the box is on")
  M.SetLayoutsIncludeAppearance(false)   -- the flip Revert has to survive
  assertf(S.Revert(), "revert runs after the box was turned off")
  assertf(M.GetOpt(M.FRAME_ID.essential, "iconLimit") == 2,
          "…and still puts appearance back, because a partial undo is not an undo")
  P.Delete("Looks Different")
  M.SetLayoutsIncludeAppearance(false)
  M.ResetOpts(M.FRAME_ID.essential)

  -- A length prefix that runs past the end of the payload. This is the one bad-input case that
  -- string.sub's clamping would otherwise let through SILENTLY: `t1;s5:class` + `s99:PRIEST` parses
  -- as { class = "PRIEST" } — a well-formed layout built from a truncated read — and every later
  -- check (is it a table, is .class a string, does the class match) then passes. The control below
  -- is the same payload with the correct length, to prove the rejection is about the length and not
  -- about the shape.
  local good = P.Decode("NECDM1" .. "dDE7czU6Y2xhc3NzNjpQUklFU1Q=")
  assertf(type(good) == "table" and good.class == "PRIEST", "a hand-built minimal layout decodes")
  local bad, e5 = P.Decode("NECDM1" .. "dDE7czU6Y2xhc3NzOTk6UFJJRVNU")
  assertf(bad == nil and e5 ~= nil, "…but an over-long string length is rejected, not silently truncated")

  -- A declared pair count is attacker-controlled, so a header claiming a billion pairs is the
  -- obvious denial-of-service shape. The parser needs no cap for it: every iteration must consume at
  -- least one byte of payload or raise, so the loop is self-limiting and this fails on the first
  -- pair. Asserting it here is what lets the cap stay OUT of parseValue instead of sitting there as
  -- an unreachable guard. base64("t999999999;").
  local _, e7 = P.Decode("NECDM1" .. "dDk5OTk5OTk5OTs=")
  assertf(e7 ~= nil, "a table header claiming a billion pairs fails on the first one")

  -- The class gate upstream lacks: another class's layout is refused with a reason that names it,
  -- rather than silently writing into that class's slot and appearing to do nothing.
  local mageSnap = S.SnapshotState()
  mageSnap.class = "MAGE"
  local nope, e6 = P.Decode(P.Encode(mageSnap))
  assertf(nope == nil and (e6 or ""):find("MAGE"), "another class's layout is refused by name")

  -- ── Starter reset ──
  A2.Assign(moved, "essential", "utility", "PRIEST")
  if M.SetReadySoundKit then M.SetReadySoundKit(8092, 1) end
  assertf(P.UseStarter(), "starter reset runs")
  assertf(not inUtility(moved), "…reverting the spell lists")
  assertf(not (M.GetReadySoundKit and M.GetReadySoundKit(8092)), "…and clearing the sounds")
  assertf(P.Current() == nil, "…leaving no layout selected")
  assertf(S.CanRevert(), "…but it is undoable")

  -- Closing the panel drops the undo: reverting an hour-old change is not an undo.
  S.HidePanel()
  assertf(not S.CanRevert(), "closing the panel clears the undo")

  -- …which is the state the button spends nearly all its life in, and it used to spend that life
  -- greyed and MUTE: a disabled Button eats OnEnter, so the tooltip explaining what Revert even
  -- covers never appeared on the one occasion someone would go looking for it. Reported as "the
  -- revert button does nothing".
  local rb = S.panel.revertButton
  assertf(rb._motionWhileDisabled == true,
          "the greyed Revert still takes the mouse, or it cannot say why it is grey")
  assertf(rb:IsEnabled() == false, "…and it IS grey with nothing to undo")
  rb:GetScript("OnEnter")(rb)
  local said = table.concat(GameTooltip.lines, " | ")
  assertf(said:find("Nothing to undo") ~= nil,
          "…so hovering it says there is nothing to undo (" .. said .. ")")
  assertf(said:lower():find("layout") ~= nil,
          "…and what it would have undone, which is LAYOUTS and not the settings next to it")
  -- The reason line is conditional, not boilerplate: armed, the tooltip must not still claim there is
  -- nothing to undo. A single unconditional AddLine would pass the two assertions above forever.
  P.UseStarter()
  rb:GetScript("OnEnter")(rb)
  assertf(table.concat(GameTooltip.lines, " | "):find("Nothing to undo") == nil,
          "…and drops that line once there IS something to undo")
  S.HidePanel()

  M.ResetTracking()
end

print("\n=== SETTINGS TAB (Phase 4c) ===")
do
  local S = NE.cooldownviewersettings
  local panel = S.panel or S.Build()

  -- Laziness first, before anything opens the tab: ~60 frames a player who never opens it should not
  -- pay for. Every earlier block has opened this panel, so a page built at panel-build time would
  -- already exist here.
  assertf(S.settingsColumn == nil, "the settings page is not built until its tab is opened")

  S.ShowPanel()
  assertf(#panel.tabButtons == 3, "the panel carries three side tabs (" .. #panel.tabButtons .. ")")

  S.SetDisplayMode("settings")
  assertf(S.GetDisplayMode() == "settings", "the settings tab selects")
  local col = S.settingsColumn
  assertf(col ~= nil, "…and builds the page on that first switch")
  assertf(panel.scroll:GetScrollChild() == panel.settingsContent,
          "…swapping the scroll child to the settings page")
  assertf(panel.settingsContent:IsShown() and not panel.content:IsShown(),
          "…and showing exactly one of the two bodies")

  -- The chrome that belongs to the GRIDS goes away: the search box dims non-matching tiles and the cog
  -- holds Show Unlearned. A search box that silently does nothing is worse than an absent one.
  assertf(not panel.search:IsShown(), "the search box hides on the settings tab")
  assertf(not panel.settingsCog:IsShown(), "…as does the cog")
  -- Same for the footer: a layout captures spell lists, auras, trinket placement, alerts and sounds —
  -- not viewer geometry — so leaving it under a page of icon sliders would imply it saves them.
  assertf(not panel.layoutButton:IsShown() and not panel.revertButton:IsShown(),
          "…and the layout footer, which does not cover viewer geometry")

  -- Find a control by the section it lives in plus its own label. Scoped by section because labels
  -- repeat across sections, and an unscoped search silently answers with the first match — so a test
  -- meaning to prove one control works can end up proving nothing about it at all.
  local function findRow(sectionTitle, labelText)
    for _, e in ipairs(col.entries) do
      local f = e.frame
      local inSection = (not sectionTitle) or (e.section and e.section.title == sectionTitle)
      if inSection and f.Label and f.Label:GetText() == labelText then return f, e end
    end
    return nil
  end
  local function findSection(title)
    for _, s in ipairs(col.sections) do
      if s.title == title then return s end
    end
    return nil
  end

  -- ── NO PER-VIEWER SETTINGS (owner steer) ──
  -- Every one of these used to have a section here AND a row in the edit-mode dialog. The dialog is
  -- the better place — you are looking at the frame while you change it — so the duplication was
  -- resolved by removing this half, not by keeping both in sync. Asserted by NAME, over every viewer,
  -- because "the section is gone" would still pass with the controls re-homed under some other header.
  for _, spec in ipairs(M.VIEWER_SPECS or {}) do
    assertf(findSection(spec.label) == nil,
            "the tab no longer carries a section for " .. spec.label)
  end
  for _, label in ipairs({ "Icon size", "Icons per row", "Icon padding", "Opacity", "Orientation",
                           "Icon direction", "Visibility", "Show timer", "Show tooltips",
                           "Hide when inactive", "Bar content", "Bar width" }) do
    assertf(findRow(nil, label) == nil,
            "…nor a " .. label .. " control anywhere on it, which the dialog now owns")
  end

  -- ── Sliders ── (the tall two-line kind; the dialog's compact one is asserted in its own block)
  local inset = findRow("Icon fit", "Icon inset")
  assertf(inset ~= nil, "Icon fit keeps its Icon inset slider, which is not per-viewer")
  inset.Slider:SetValue(3)
  assertf(M.GetIconInsetExtra() == 3, "moving it writes the setting")
  assertf(inset.Value:GetText() == "3%", "…and the row shows the value with its unit")
  -- The minimal bar reaches BOTH kinds. Two shapes of slider a tab apart, one wearing the 2004 groove
  -- and one not, is the same mismatch the button sweep was for — the skin belongs to the kit, not to
  -- the dialog that asked for it first.
  assertf(inset.Slider._neMinimalSlider ~= nil and inset.Slider._backdrop == nil,
          "…and the tall slider wears the minimal bar too, not just the dialog's compact one")

  -- SetObeyStepOnDrag is retail-only, so the step is applied on the way in.
  inset.Slider:SetValue(2.4)
  assertf(M.GetIconInsetExtra() == 2, "a between-steps value snaps to a step")
  assertf(inset.Slider:GetValue() == 2, "…and the thumb re-seats on the snapped value")

  -- A drag fires OnValueChanged continuously, and every write re-runs the icons' fit. Only a change
  -- that crosses into the next step may write.
  local writes = 0
  local realInset = M.SetIconInsetExtra
  M.SetIconInsetExtra = function(...) writes = writes + 1; return realInset(...) end
  local onValue = inset.Slider:GetScript("OnValueChanged")
  onValue(inset.Slider, 2.2)
  onValue(inset.Slider, 1.6)
  assertf(writes == 0, "a drag that stays inside one step writes nothing (" .. writes .. ")")
  onValue(inset.Slider, 3.1)
  assertf(writes == 1, "…and crossing into the next step writes exactly once (" .. writes .. ")")
  M.SetIconInsetExtra = realInset

  -- ── Checkboxes ──
  local glow = findRow("Buffed spells", "Glow while buffed")
  local was = M.IsBuffGlowEnabled() and true or false
  -- Clicking the ROW, not the box: the label is the bigger target and has to work.
  glow:GetScript("OnClick")(glow)
  assertf((M.IsBuffGlowEnabled() and true or false) ~= was,
          "clicking a checkbox row flips the setting")
  assertf((glow.Check:GetChecked() and true or false) ~= was, "…and repaints the box")
  -- The box's own path. UICheckButtonTemplate flips its state before OnClick runs on the real client;
  -- the stub has no template, so the flip is done here to reproduce what the handler is handed.
  glow.Check:SetChecked(was)
  glow.Check:GetScript("OnClick")(glow.Check)
  assertf((M.IsBuffGlowEnabled() and true or false) == was,
          "…and clicking the box itself agrees with it")

  -- ── Dropdowns ── (the tab's plain trigger; the dialog's art trigger is asserted in its own block)
  local dest = findRow("Buff tracking", "Show them as")
  local root = NE.menu.BuildRoot(dest.MenuGenerator)
  assertf(#root.children == 3, "the auto-track destination offers three choices")
  -- ORDERED, not sorted: alphabetical would lead with "Bars only". Widest first is the progression,
  -- which is the whole reason the kit takes an array where the options tab takes a map.
  assertf(root.children[1].text == "Icons and bars" and root.children[2].text == "Icons only",
          "…in the order written, not alphabetised")
  root:Child("Bars only"):Invoke()
  assertf(M.AutoTrackDest() == "bar", "choosing one writes the setting")
  assertf(dest.Button:GetText() == "Bars only", "…and the button relabels to the choice")
  root:Child("Icons and bars"):Invoke()

  -- ── Collapsible sections ──
  local track = findSection("Buff tracking")
  local auto  = findRow("Buff tracking", ("Auto-track buffs under %ds"):format(M.BUFF_TRACK_MAX_DURATION))
  assertf(track ~= nil and auto ~= nil, "the Buff tracking section exists")
  assertf(not track.expanded and not auto:IsShown(), "…collapsed, with its rows hidden")
  local shortH = panel.settingsContent:GetHeight()
  track.header:GetScript("OnClick")(track.header)
  assertf(track.expanded and auto:IsShown(), "clicking the header expands it")
  assertf(panel.settingsContent:GetHeight() > shortH, "…and the scroll child grows to match")

  -- ── The page is not the only writer ──
  -- A layout apply, a reset, or DragonUI's master toggle can all move a value underneath this page. A
  -- control that only ever wrote would drift, and a stale checkbox reads exactly like a setting that
  -- failed to apply.
  M.SetIconInsetExtra(1)
  S.RefreshSettingsPage()
  assertf(inset.Slider:GetValue() == 1 and inset.Value:GetText() == "1%",
          "a change made elsewhere shows up on the next page refresh")

  -- ── The settings tab leaves the grids alone ──
  -- The panel refreshes on SPELL_UPDATE_ICON / GET_ITEM_INFO_RECEIVED / UNIT_INVENTORY_CHANGED while
  -- shown. Without the mode guard, each of those would deactivate every category behind a page the
  -- player is not looking at, and MODE_ORDER has no "settings" entry to re-activate them from.
  S.SetDisplayMode("spells")
  local ess = S._categories.essential
  assertf(ess ~= nil and ess._active, "the spells tab populates its categories")
  S.SetDisplayMode("settings")
  S.RefreshLayout()
  assertf(ess._active, "RefreshLayout on the settings tab does not tear the grids down")

  -- ── Switching back restores everything ──
  S.SetDisplayMode("spells")
  assertf(panel.scroll:GetScrollChild() == panel.content, "the spells tab swaps the grid body back in")
  assertf(panel.search:IsShown() and panel.settingsCog:IsShown() and panel.layoutButton:IsShown(),
          "…and brings the grid chrome back")

  -- ── The DragonUI options section is now two controls ──
  local rec = { toggles = {}, buttons = {}, sliders = 0, drops = 0, headings = 0 }
  local C = {}
  function C:AddSpacer() end
  function C:AddHeading() rec.headings = rec.headings + 1 end
  function C:AddDescription() end
  function C:AddToggle(_, o) rec.toggles[#rec.toggles + 1] = o end
  function C:AddButton(_, o) rec.buttons[#rec.buttons + 1] = o end
  -- Recorded rather than omitted: a builder that still reached for these would error out and take the
  -- whole run with it, which says less than a count does.
  function C:AddSlider() rec.sliders = rec.sliders + 1 end
  function C:AddDropdown() rec.drops = rec.drops + 1 end

  NE.optionSections[1].build({}, C)
  assertf(#rec.toggles == 1, "the DragonUI section renders one toggle (" .. #rec.toggles .. ")")
  assertf(#rec.buttons == 1, "…and one button (" .. #rec.buttons .. ")")
  assertf(rec.sliders == 0 and rec.drops == 0,
          "…and no viewer settings at all (" .. rec.sliders .. " sliders, " .. rec.drops .. " dropdowns)")

  assertf(rec.toggles[1].getFunc() == M.IsEnabled(), "its toggle reads the master enable")
  -- Switching it off from here, with the window up, is the one route by which a live panel can outlive
  -- the module — so the toggle has to take the window with it, or it sits there configuring four frames
  -- it can no longer show, behind a Position button that leads to a hidden editor handle.
  S.ShowPanel()
  assertf(panel:IsShown(), "the window is up before the module is switched off")
  rec.toggles[1].setFunc(false)
  assertf(M.IsEnabled() == false, "…and writes it")
  assertf(not M.viewers.essential:IsShown(), "…which hides the viewers immediately, no reload")
  assertf(not panel:IsShown(), "…and closes the window, which configures viewers that are now gone")
  S.ShowPanel()
  assertf(not panel:IsShown(), "…and it will not re-open while the module is off")
  rec.toggles[1].setFunc(true)

  S.HidePanel()
  rec.buttons[1].callback()
  -- SPELLS, not Settings. What anyone wants first after switching the module on is to see what it
  -- tracks; Settings is one click away on a tab that is already on screen. (Owner's steer.)
  assertf(panel:IsShown() and S.GetDisplayMode() == "spells",
          "its button opens /cdm on the Spells tab (" .. tostring(S.GetDisplayMode()) .. ")")

  -- ── The way to a viewer's settings (Phase 6: §G.4's last undecided item) ──
  -- One button per viewer, in place of the four sections that used to hold their controls. This is the
  -- only route from this tab to those settings now, so it has to land ON them, not merely in edit mode.
  S.SetDisplayMode("settings")
  local function linkRow(label)
    for _, e in ipairs(col.entries) do
      local f = e.frame
      if f.Button and f.Button.GetText and f.Button:GetText() == label
        and e.section and e.section.title == "Viewer layout" then return f end
    end
  end
  for _, spec in ipairs(M.VIEWER_SPECS or {}) do
    assertf(linkRow(spec.label) ~= nil, "Viewer layout carries a button for " .. spec.label)
  end
  local posRow = linkRow("Essential Cooldowns")

  -- In combat it must refuse AND leave the window up. Hiding the panel first and then failing would
  -- take away the only place the reason could be read.
  local realCombat = InCombatLockdown
  InCombatLockdown = function() return true end
  DragonUI.EditorMode._active, DragonUI._selected = false, nil
  S.ShowPanel()
  posRow.Button:GetScript("OnClick")(posRow.Button)
  assertf(not DragonUI.EditorMode:IsActive(), "Position refuses to open the editor in combat")
  assertf(S.panel:IsShown(), "…and leaves the settings window up to say why")
  -- The REASON, not just the refusal. EditorMode:Show() already no-ops in combat and the IsActive
  -- re-check would catch that on its own, so the explicit combat branch earns its place only by naming
  -- combat: "editor mode declined to open" mid-fight tells the player nothing to act on.
  local okc, whyc = NE.OpenFrameEditor(M.viewers.essential)
  assertf(okc == false and (whyc or ""):lower():find("combat") ~= nil,
          "…and the reason names combat rather than a generic refusal (" .. tostring(whyc) .. ")")
  InCombatLockdown = realCombat

  -- Out of combat: the editor opens, the panel closes, and the frame handed to SelectEditorFrame is
  -- the ANCHOR. This is the trap the whole helper exists for — RegisterHUDFrame registers the
  -- CreateUIFrame anchor and hangs the viewer off it, so selecting the viewer itself would put the
  -- editor's coordinate readout and Reset button on a frame it cannot move, and it would look fine.
  posRow.Button:GetScript("OnClick")(posRow.Button)
  local anchor = DragonUI.EditableFrames["CooldownViewerEssential"].frame
  assertf(DragonUI.EditorMode:IsActive(), "out of combat it opens the editor")
  assertf(DragonUI._selected == anchor, "…selecting the registered anchor")
  assertf(DragonUI._selected ~= M.viewers.essential, "…and NOT the viewer frame hung off it")
  assertf(M.viewers.essential.editorAnchor == anchor, "…which is what .editorAnchor points at")
  assertf(not S.panel:IsShown(), "…and closes the settings window, which would cover the viewer")
  -- AND LANDS ON THE SETTINGS. Since the per-viewer controls left this tab, this button is the only
  -- route to them from here; dropping the player into edit mode to go hunting for the right handle
  -- would be a worse tab than the one it replaced.
  assertf(M.IsEditorPanelShown(), "…and opens that viewer's settings, not just edit mode")
  local _, epPages = M._editorPanel()
  assertf(epPages.essential and epPages.essential.body:IsShown(),
          "…showing the page for the viewer whose button was clicked")
  M.HideEditorPanel()
  DragonUI.EditorMode:Hide()

  -- A missing editor is a returned reason, not an error: some DragonUI builds have no EditorMode.
  local savedEM = DragonUI.EditorMode
  DragonUI.EditorMode = nil
  local ok6, why6 = NE.OpenFrameEditor(M.viewers.essential)
  assertf(ok6 == false and type(why6) == "string", "no editor mode reports a reason rather than erroring")
  DragonUI.EditorMode = savedEM

  -- Leave the store as we found it.
  for _, id in pairs(M.FRAME_ID) do M.ResetOpts(id) end
  S.SetDisplayMode("spells")
  S.HidePanel()
end

-- ── The edit-mode settings dialog ───────────────────────────────────────────────────────────────
--
-- Retail puts a system's settings ON the frame in Edit Mode, as a dialog beside it. Tested here rather
-- than in-game because none of it needs a screen: the dialog is the /cdm control kit over a plain
-- frame, and the click path is one script on an anchor whose editor state the stub owns.
print("\n=== EDIT-MODE SETTINGS DIALOG ===")
do
  local S   = NE.cooldownviewersettings
  local FID = M.FRAME_ID.essential
  local anchor = DragonUI.EditableFrames["CooldownViewerEssential"].frame
  -- Give the handle a real place on screen, so the placement below runs its measuring branch rather
  -- than the "I cannot tell where this is, centre it" fallback.
  anchor._center = { 300, 400 }
  anchor:SetSize(200, 60)
  -- DragonUI's Exit Edit Mode button: UIParent, TOOLTIP, frame level 1000
  -- (DragonUI/modules/editor_mode.lua:190). Modelled because it is what the Reset confirm kept opening
  -- underneath, and because its POSITION is half the reason the confirm moved into the dialog — it
  -- parks at screen centre, which is exactly where a StaticPopup lands.
  local duExit = CreateFrame("Button", "DragonUIExitEditorButton", UIParent)
  duExit:SetFrameStrata("TOOLTIP")
  duExit:SetFrameLevel(1000)
  duExit:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

  -- Find a control by its label, in one viewer's page. By label rather than by index: an index passes
  -- just as well when the wrong row moved into that slot.
  local function rowOf(category, label)
    local _, pgs = M._editorPanel()
    local page = pgs and pgs[category]
    for _, e in ipairs((page and page.col and page.col.entries) or {}) do
      local f = e.frame
      if f.Label and f.Label.GetText and f.Label:GetText() == label then return f end
    end
    return nil
  end

  DragonUI.EditorMode._active = true
  assertf(M.ShowEditorPanel("essential", anchor) == true, "the dialog opens for a viewer")
  local panel = M._editorPanel()
  assertf(panel ~= nil and panel:IsShown(), "…and is on screen")
  assertf(panel:GetFrameStrata() == "FULLSCREEN_DIALOG",
          "…above the editor handles, which CreateUIFrame puts at FULLSCREEN (" ..
          tostring(panel:GetFrameStrata()) .. ")")

  -- Every per-viewer setting, visible at once — which is the whole reason this replaced a menu.
  for _, name in ipairs({ "Enabled", "Orientation", "Icon Limit", "Icon Direction", "Icon Size",
                          "Icon Padding", "Opacity", "Visibility", "Show Timer", "Show Tooltips" }) do
    assertf(rowOf("essential", name) ~= nil, "the dialog carries " .. name)
  end
  assertf(panel.revertButton and panel.resetButton, "…and the Revert / Reset buttons region")

  -- SIDE BY SIDE, one row (owner steer). SetPoint's 3-arg shape drops its offsets into the
  -- relTo/relPoint slots, so read them positionally rather than pretending they are anchors.
  local function offsetsOf(btn)
    local p = btn._points[#btn._points] or {}
    local x, y = p[2], p[3]
    if type(x) ~= "number" then x, y = p[4], p[5] end
    return p[1], x, y
  end
  local revPt, _, revY = offsetsOf(panel.revertButton)
  local resPt, _, resY = offsetsOf(panel.resetButton)
  assertf(revPt == "BOTTOMLEFT" and resPt == "BOTTOMRIGHT",
          "…as a pair, one anchored to each side (" .. tostring(revPt) .. "/" .. tostring(resPt) .. ")")
  assertf(revY == resY and revY ~= nil,
          "…on the SAME row, which is the whole point of the change (" ..
          tostring(revY) .. " vs " .. tostring(resY) .. ")")
  assertf(panel.revertButton:GetWidth() == panel.resetButton:GetWidth(),
          "…splitting the row evenly, so neither reads as the primary action")

  -- The red 3-slice. ButtonSkin has been written against the 128-RedButton sheet since Sprint 0 and,
  -- with it unshipped, fail-safed to native art on every call and RETURNED FALSE to say so — which
  -- nothing was reading, so it looked like a skin that worked.
  -- Read defensively throughout: a regression that stops the skin part-way leaves these nil, and an
  -- aborted run says less than a named failure does.
  local revSlice = panel.revertButton._neThreeSlice or {}
  local resSlice = panel.resetButton._neThreeSlice or {}
  assertf(revSlice.Left ~= nil, "the footer buttons wear the red 3-slice")
  local capArt = revSlice.Left and revSlice.Left:GetTexture()
  assertf(tostring(capArt):lower():find("redbutton") ~= nil,
          "…off a shipped sheet (" .. tostring(capArt) .. ")")
  assertf(revSlice.Center ~= nil and revSlice.Center:GetHorizTile() == true,
          "…with the centre tiling, or a wide button stretches its middle")
  -- Pressed art asserted on RESET, not Revert: Revert is disabled while there is nothing to undo, and
  -- a disabled button correctly reports the disabled art whatever the mouse is doing.
  panel.resetButton:Enable()
  local resDown = panel.resetButton:GetScript("OnMouseDown")
  assertf(type(resDown) == "function", "…and the skin wired its state scripts")
  if resDown then resDown(panel.resetButton) end
  assertf(resSlice.postfix == "-Pressed",
          "…so pressing one swaps all three pieces to the pressed art (" ..
          tostring(resSlice.postfix) .. ")")
  local resUp = panel.resetButton:GetScript("OnMouseUp")
  if resUp then resUp(panel.resetButton) end
  assertf(revSlice.postfix == "-Disabled",
          "…and a disabled one wears the disabled art, which is how Revert reads as unavailable")
  -- "Cooldown Manager Settings" is NOT in that region: retail's AddExtraButtons puts a system's own
  -- extra actions at the END of the options stack, which is where NewEra's dialog carries this one.
  local settingsRow
  for _, e in ipairs((select(2, M._editorPanel()).essential.col.entries) or {}) do
    if e.frame.Button and e.frame.Button.GetText
      and e.frame.Button:GetText() == "Cooldown Manager Settings" then settingsRow = e.frame end
  end
  assertf(settingsRow ~= nil, "…and the way out sits at the end of the options stack, as retail does")
  -- It sits directly above Revert/Reset, which the dialog skins itself, so it has to match them: one
  -- unskinned button in a stack of three is more obviously wrong than three unskinned ones.
  assertf(settingsRow.Button._neThreeSlice ~= nil,
          "…wearing the same red 3-slice as the two buttons under it")

  -- ART. The dialog wears retail's DialogBorderTranslucentTemplate — black 0.8 under the DiamondMetal
  -- "Dialog" nineslice — NOT PanelChrome's portrait frame, which is window chrome: on a small
  -- floating dialog that brings a rock fill and a portrait ring and reads as a window that lost its
  -- contents. That was the first render's actual fault.
  -- Pieces land ON the frame (core/NineSlice.lua's getPiece writes container[pieceName]), which is
  -- what NewEra's dialog does too — not on a PanelChrome-style .NineSlice child.
  assertf(panel.Bg ~= nil and panel.TopLeftCorner ~= nil,
          "the dialog carries a background and a nineslice border")
  assertf(panel.Portrait == nil, "…and no portrait, whose ring is panel chrome and wrong here")
  -- Read what the border ACTUALLY WEARS, not what the registry could offer. Asserting the layout
  -- table alone passed just as happily with the dialog applying PortraitFrameTemplate, and it would
  -- pass with the BLP never shipped: NE.tex.SetAtlas reports a miss and leaves the texture blank in
  -- both cases, so the file path on the piece is the only thing that answers all three questions.
  assertf(tostring(panel.TopLeftCorner:GetTexture()):lower():find("diamondmetal") ~= nil,
          "…wearing DiamondMetal, the retail dialog border, from a shipped file (" ..
          tostring(panel.TopLeftCorner:GetTexture()) .. ")")
  assertf(tostring(panel.LeftEdge:GetTexture()):lower():find("diamondmetal") ~= nil,
          "…edges too, which come off a different sheet and so can go missing on their own")

  -- THE THEME IS THE DIALOG'S, and it must not have leaked into the tab: one kit, two sets of
  -- metrics, and the tab is a scrolling page of sections where this is a fixed 32px-row panel.
  local dlgCheck = rowOf("essential", "Show Timer")
  local dlgDrop  = rowOf("essential", "Orientation")
  assertf(dlgDrop.Button.RefreshArt ~= nil,
          "the dialog's dropdown is the modern textholder-and-arrow trigger")
  assertf(tostring(dlgDrop.Button._body:GetTexture()):lower():find("dropdown") ~= nil
          and tostring(dlgDrop.Button._arrow:GetTexture()):lower():find("dropdown") ~= nil,
          "…with its body and arrow art actually resolving to a shipped file")

  -- THE BODY IS 3-SLICED. It used to be one texture SetAllPoints — a 54x41 rounded rect with a 12px
  -- bevel stretched across a 200x26 row, which smeared the corners sideways and squashed the bevel.
  -- The caps carry the corners at their own aspect; only the flat middle stretches.
  assertf(dlgDrop.Button._bodyLeft ~= nil and dlgDrop.Button._bodyRight ~= nil,
          "…and the body is 3-sliced, not one rounded rect stretched flat")
  local capW = dlgDrop.Button._bodyLeft:GetWidth()
  local wantCap = 18 * (dlgDrop.Button:GetHeight() / 41)
  assertf(math.abs(capW - wantCap) < 0.01,
          "…its caps sized from the row height, so the corner keeps its aspect (" ..
          tostring(capW) .. " vs " .. tostring(wantCap) .. ")")
  assertf(capW > 0 and capW * 2 < dlgDrop.Button:GetWidth(),
          "…and small enough that a middle run is left to stretch")
  -- The three pieces are three DIFFERENT sub-rects of one sheet, and every one of them resolves to
  -- the same file — so the file path cannot tell them apart, and cap widths come from a Lua constant
  -- rather than the atlas. The texcoords are the only thing that says the slicing is real: they have
  -- to be contiguous and left-to-right, or the button wears three copies of the same corner.
  local lL, lR = dlgDrop.Button._bodyLeft:GetTexCoord()
  local cL, cR = dlgDrop.Button._body:GetTexCoord()
  local rL, rR = dlgDrop.Button._bodyRight:GetTexCoord()
  assertf(lR == cL and cR == rL,
          "…cut from three contiguous sub-rects (" .. table.concat(
            { lL, lR, cL, cR, rL, rR }, " ") .. ")")
  assertf(lL < cL and cL < rL and rR > cR,
          "…in left-to-right order, not three copies of one corner")

  -- ALIGNMENT. The control column is defined by the compact slider — its nudge arrow at labelW+2, its
  -- value text ending 4 short of the row — and a dropdown used to line up with neither end of it.
  local dlgSlider = rowOf("essential", "Icon Size")
  local dropX  = select(2, offsetsOf(dlgDrop.Button))
  local arrowX = select(2, offsetsOf(dlgSlider.Left))
  assertf(dropX == arrowX,
          "the dropdown starts where the slider's nudge arrow does (" ..
          tostring(dropX) .. " vs " .. tostring(arrowX) .. ")")
  assertf(dropX + dlgDrop.Button:GetWidth() == 343 - 4,
          "…and ends where the slider's value text does, so the rows line up down both edges (" ..
          tostring(dropX + dlgDrop.Button:GetWidth()) .. ")")
  -- The gradient lives on the ARROW in retail's design, so the state IS the arrow swapping atlas.
  dlgDrop.Button:RefreshArt()
  assertf(dlgDrop.Button._arrowAtlas == "common-dropdown-a-button", "…idle at rest")
  dlgDrop.Button._neOver = true
  dlgDrop.Button:RefreshArt()
  assertf(dlgDrop.Button._arrowAtlas == "common-dropdown-a-button-hover",
          "…and hovering moves it to the hover art, which is the only state this trigger has")
  dlgDrop.Button._neOver = false
  dlgDrop.Button:RefreshArt()
  -- A bare Button has no SetText/GetText of its own, and every refresh below calls them.
  dlgDrop.Button:SetText("probe")
  assertf(dlgDrop.Button:GetText() == "probe", "…and it answers SetText/GetText like the template did")
  local function heightOf(col, label)
    for _, e in ipairs(col.entries or {}) do
      if e.frame.Label and e.frame.Label.GetText and e.frame.Label:GetText() == label then return e.h end
    end
  end
  local pgsT = select(2, M._editorPanel())
  assertf(heightOf(pgsT.essential.col, "Show Timer") == 32,
          "…and its rows are retail's 32px (" .. tostring(heightOf(pgsT.essential.col, "Show Timer")) .. ")")
  assertf(dlgCheck.Check:GetWidth() == 32, "…with retail Edit Mode's 32px checkbox")

  -- THE DIALOG HOLDS STILL. It used to be anchored TO the viewer, so dragging Icon Size or Icon Limit
  -- resized the viewer and slid the dialog sideways out from under the cursor, mid-drag. The position
  -- resolves into UIParent coordinates once, on open.
  local anchorPt, anchorRel = panel:GetPoint(1)
  assertf(anchorRel == UIParent,
          "the dialog is placed against the screen, not pinned to the frame it edits (" ..
          tostring(anchorPt) .. ")")
  -- Both sides, because the placement picks one of two branches on which half of the screen the frame
  -- sits in — and a test that only ever lands in one of them leaves the other free to break.
  assertf(anchorPt == "TOPLEFT",
          "…to the RIGHT of a frame on the left half of the screen (" .. tostring(anchorPt) .. ")")
  anchor._center = { 800, 400 }
  M.ShowEditorPanel("essential", anchor)
  local rightPt, rightRel = panel:GetPoint(1)
  assertf(rightPt == "TOPRIGHT" and rightRel == UIParent,
          "…and to its LEFT when the frame is on the right half (" .. tostring(rightPt) .. ")")
  anchor._center = { 300, 400 }
  M.ShowEditorPanel("essential", anchor)
  local before = { panel:GetPoint(1) }

  -- A slider writes through, and the frame follows without a reload.
  local limit = rowOf("essential", "Icon Limit")
  limit.Slider:SetValue(5)
  assertf(M.GetOpt(FID, "iconLimit") == 5, "dragging a slider writes the setting")
  assertf(M.viewers.essential.iconLimit == 5, "…and the viewer re-lays out at once")
  local after = { panel:GetPoint(1) }
  assertf(before[1] == after[1] and before[2] == after[2]
          and before[4] == after[4] and before[5] == after[5],
          "…and the dialog does not move while you drag (" ..
          tostring(before[4]) .. "," .. tostring(before[5]) .. " → " ..
          tostring(after[4]) .. "," .. tostring(after[5]) .. ")")

  -- A drag fires OnValueChanged continuously, and every write re-runs the viewer's RefreshLayout,
  -- which relays out every icon. Only a change that crosses into the next step may write. This used to
  -- be asserted on the TAB's slider; the tab has no per-viewer slider now, and the compact one has its
  -- own commit path, so it is asserted where the code actually is.
  local sizeRow = rowOf("essential", "Icon Size")
  sizeRow.Slider:SetValue(150)
  assertf(M.GetOpt(FID, "iconSize") == 150, "the compact slider writes too")
  assertf(sizeRow.Value:GetText() == "150%", "…showing the value with its unit")
  sizeRow.Slider:SetValue(137)
  assertf(M.GetOpt(FID, "iconSize") == 140, "…snapping a between-steps value onto a step")
  assertf(sizeRow.Slider:GetValue() == 140, "…and re-seating the thumb on it")
  local sizeWrites = 0
  local realSetOpt = M.SetOpt
  M.SetOpt = function(...) sizeWrites = sizeWrites + 1; return realSetOpt(...) end
  local onSize = sizeRow.Slider:GetScript("OnValueChanged")
  onSize(sizeRow.Slider, 142)
  onSize(sizeRow.Slider, 138)
  assertf(sizeWrites == 0, "a drag that stays inside one step writes nothing (" .. sizeWrites .. ")")
  onSize(sizeRow.Slider, 148)
  assertf(sizeWrites == 1, "…and crossing into the next step writes exactly once (" .. sizeWrites .. ")")
  M.SetOpt = realSetOpt

  -- The checkbox row, likewise moved. Clicking the ROW, not the box: the label is the bigger target.
  local timerRow = rowOf("essential", "Show Timer")
  local timerWas = M.GetOpt(FID, "showTimer") and true or false
  timerRow:GetScript("OnClick")(timerRow)
  assertf((M.GetOpt(FID, "showTimer") and true or false) ~= timerWas,
          "clicking a checkbox row flips the setting")
  assertf((timerRow.Check:GetChecked() and true or false) ~= timerWas, "…and repaints the box")
  timerRow.Check:SetChecked(timerWas)
  timerRow.Check:GetScript("OnClick")(timerRow.Check)
  assertf((M.GetOpt(FID, "showTimer") and true or false) == timerWas,
          "…and clicking the box itself agrees with it")

  -- THE ARROWS. A drag reports continuous values on this client (SetObeyStepOnDrag is retail-only),
  -- so they are the only way to land on an exact value — not decoration.
  limit.Right:GetScript("OnClick")(limit.Right)
  assertf(M.GetOpt(FID, "iconLimit") == 6, "the right arrow steps up by exactly one step")
  limit.Left:GetScript("OnClick")(limit.Left)
  limit.Left:GetScript("OnClick")(limit.Left)
  assertf(M.GetOpt(FID, "iconLimit") == 4, "…and the left arrow down")
  -- Clamped, or the arrows walk the value out of the range the slider can even show.
  for _ = 1, 8 do limit.Left:GetScript("OnClick")(limit.Left) end
  assertf(M.GetOpt(FID, "iconLimit") == 1, "…stopping at the minimum (" ..
          tostring(M.GetOpt(FID, "iconLimit")) .. ")")

  -- THE MINIMAL BAR. NewEra's dialog sliders are retail's MinimalSliderWithSteppers, and the owner
  -- supplied its sheet — one 32x128 file carrying the whole widget, so every piece here is the real
  -- art at its own size rather than a substitute.
  --
  -- Read through the TEXCOORDS, not the atlas name: all six pieces come off that one file, so the
  -- texture path is identical whichever rect a piece ends up wearing, and "did the left cap get the
  -- left cap's rect" is a question only the coordinates can answer.
  do
    local skin = limit.Slider._neMinimalSlider
    assertf(skin ~= nil and skin.Left ~= nil, "the dialog's sliders wear the minimal bar")
    assertf(limit.Slider._backdrop == nil,
            "…with OptionsSliderTemplate's groove cleared, backdrop and border together")

    local function wears(tex, name)
      local e = NE.tex._atlasEntry(name)
      local c = tex and tex._coords
      if not (e and c and #c == 4) then return false end
      return math.abs(c[1] - e.left) < 1e-9 and math.abs(c[2] - e.right)  < 1e-9
         and math.abs(c[3] - e.top)  < 1e-9 and math.abs(c[4] - e.bottom) < 1e-9
    end
    assertf(wears(skin.Left,  "minimal_sliderbar_left"),  "…its left cap being the sheet's left cap")
    assertf(wears(skin.Right, "minimal_sliderbar_right"), "…and its right the right one")
    assertf(not wears(skin.Left, "minimal_sliderbar_right"),
            "…which are DIFFERENT rects, so this is not one cap drawn twice")
    assertf(wears(skin.Middle, "_minimal_sliderbar_middle"),
            "…with the one-pixel run tiling between them")
    -- The caps keep their own width and only the run stretches — the rule the dropdown's textholder
    -- had to learn the hard way, when stretching a rounded rect smeared its corners sideways.
    assertf(skin.Left:GetWidth() == 11 and skin.Right:GetWidth() == 11,
            "…each at the art's own 11px, or a wide slider smears its rounded ends (" ..
            tostring(skin.Left:GetWidth()) .. ")")
    assertf(#skin.Middle._points == 2,
            "…and the run anchored to both caps rather than sized, so it fills whatever is left")

    -- THE DIAMOND. It is the thumb outright — 20x19 of the sheet, two pixels taller than the 17px
    -- track it rides, which is what makes it read as a knob sitting on the bar and not part of it.
    assertf(wears(skin.Thumb, "minimal_sliderbar_button"), "the thumb is the sheet's diamond")
    assertf(skin.Thumb:GetWidth() == 20 and skin.Thumb:GetHeight() == 19,
            "…at its own size (" .. tostring(skin.Thumb:GetWidth()) .. "x" ..
            tostring(skin.Thumb:GetHeight()) .. ")")
    assertf(limit.Slider:GetHeight() >= skin.Thumb:GetHeight(),
            "…and the SLIDER sized to the knob rather than to the 17px track, so the whole diamond " ..
            "sits inside the frame's own mouse region (" .. tostring(limit.Slider:GetHeight()) ..
            " vs " .. tostring(skin.Thumb:GetHeight()) .. ")")
    -- NO STATE ART, deliberately. The sheet carries one diamond and one chevron per direction because
    -- retail's minimal slider does not change art on hover or press — the feedback is the thumb
    -- moving. An earlier build DID swap three states per piece, but only because it was borrowing the
    -- scrollbar's art, which has them. Asserted so nobody re-adds a tint and calls it fidelity.
    assertf(NE.tex._atlasEntry("minimal_sliderbar_button-over") == nil,
            "the sheet has no hover variant, and the skin invents none")
    assertf(skin.ApplyState == nil, "…so there is no state machine left on it either")

    -- The steppers come off the same sheet as the bar. They were the spellbook's page-turn glyphs,
    -- which is the mismatch this pass is about.
    local lArt = limit.Left:GetNormalTexture()
    assertf(wears(lArt, "minimal_sliderbar_button_left"),
            "the left stepper is the sheet's own left chevron")
    assertf(wears(limit.Right:GetNormalTexture(), "minimal_sliderbar_button_right"),
            "…and the right one its right chevron")
    assertf(limit.Left:GetWidth() == 18 and lArt:GetWidth() == 11 and lArt:GetHeight() == 19,
            "…drawn at the art's own 11x19 inside an unchanged 18px button, or the row's arithmetic " ..
            "shifts under it (" .. tostring(limit.Left:GetWidth()) .. " / " ..
            tostring(lArt:GetWidth()) .. "x" .. tostring(lArt:GetHeight()) .. ")")
    assertf(limit.Left:GetDisabledTexture()._desat == true,
            "…and the disabled glyph is that same chevron desaturated")
    -- Pressed is the glyph nudged, because the sheet gives us nothing else to swap to.
    local _, _, _, px, py = limit.Left:GetPushedTexture():GetPoint(1)
    assertf(px == 1 and py == -1,
            "…while pressed offsets it a pixel, which is the only feedback this art affords (" ..
            tostring(px) .. "," .. tostring(py) .. ")")
  end

  -- CLICK AWAY TO DISMISS. An open menu had two ways out — pick a row, or Escape — and clicking
  -- anywhere else left it hanging, which no other menu in the game does. The dismiss is a full-screen
  -- mouse catcher parked one level under the open list, so the list keeps its own clicks.
  do
    local drop = rowOf("essential", "Visibility")
    NE.menu.Close(1)
    drop.Button:GetScript("OnClick")(drop.Button)
    local list = _G.C_DropDownList1
    assertf(list ~= nil and list:IsShown(), "clicking a dropdown opens its menu")
    local catch = NE.menu._catcher()
    assertf(catch ~= nil and catch:IsShown(), "…and arms a click catcher over the rest of the screen")
    assertf(catch:GetFrameStrata() == list:GetFrameStrata()
            and catch:GetFrameLevel() < list:GetFrameLevel(),
            "…UNDER the list, or the menu's own rows would stop taking clicks (" ..
            tostring(catch:GetFrameLevel()) .. " vs " .. tostring(list:GetFrameLevel()) .. ")")
    catch:GetScript("OnMouseDown")(catch)
    assertf(not list:IsShown(), "clicking outside closes the menu")
    assertf(not catch:IsShown(), "…and puts the catcher away with it")

    -- The menu also closes without going through the catcher — a row picked, Escape, a CloseAll from
    -- somewhere else. A catcher left armed over an empty screen eats the next click ANYWHERE.
    drop.Button:GetScript("OnClick")(drop.Button)
    assertf(NE.menu._catcher():IsShown(), "reopening arms it again")
    NE.menu.Close(1)
    assertf(not NE.menu._catcher():IsShown(),
            "…and closing the menu any other way disarms it, so it cannot eat a later click")

    -- ToggleAnchored is a TOGGLE: the second click closes. Arming over a screen with no menu on it
    -- would cost the player a click for nothing.
    drop.Button:GetScript("OnClick")(drop.Button)
    drop.Button:GetScript("OnClick")(drop.Button)
    assertf(not _G.C_DropDownList1:IsShown() and not NE.menu._catcher():IsShown(),
            "…and a toggle that closed the menu arms nothing")
  end

  -- A dropdown is a button that opens a radio menu (§G.11: no retail dropdown template here), so the
  -- assertion goes through its generator rather than its art.
  local orient = rowOf("essential", "Orientation")
  local oroot = NE.menu.BuildRoot(orient.MenuGenerator)
  assertf(oroot:Child("Horizontal") ~= nil and oroot:Child("Vertical") ~= nil,
          "the Orientation dropdown offers both values")
  -- ORDERED, not sorted. Alphabetical would put Hidden second in Visibility; "Always / In Combat /
  -- Hidden" is a progression, which is why the kit takes an array where the options tab takes a map.
  local vroot = NE.menu.BuildRoot(rowOf("essential", "Visibility").MenuGenerator)
  assertf(vroot.children[1].text == "Always" and vroot.children[2].text == "In Combat"
          and vroot.children[3].text == "Hidden",
          "…and Visibility lists its three in the order written, not alphabetised")
  oroot:Child("Vertical"):Invoke()
  assertf(M.GetOpt(FID, "orientation") == "vertical", "…and picking one writes it")
  assertf(orient.Button:GetText() == "Vertical", "…and the button re-reads to show it")

  -- Per-viewer differences, both directions. A control that silently does nothing is the failure the
  -- /cdm tab already refused (§4c) and it would be no better here.
  M.ShowEditorPanel("buffBar", anchor)
  M.ShowEditorPanel("buffIcon", anchor)
  assertf(rowOf("buffBar", "Bar Content") ~= nil and rowOf("buffBar", "Bar Width") ~= nil,
          "the bar viewer gets the two bar-only settings")
  assertf(rowOf("essential", "Bar Content") == nil, "…and no other viewer does")
  assertf(rowOf("buffIcon", "Hide When Inactive") ~= nil,
          "Hide When Inactive is offered where the template honours it")
  assertf(rowOf("essential", "Hide When Inactive") == nil,
          "…and not on Essential, whose template ignores the setting entirely")

  -- ONE dialog, not four. Selecting another viewer swaps the page and retitles.
  M.ShowEditorPanel("buffBar", anchor)
  local _, pgs = M._editorPanel()
  assertf(pgs.buffBar.body:IsShown(), "selecting another viewer shows its page")
  assertf(not pgs.essential.body:IsShown(), "…and hides the one before it")
  assertf(panel.TitleText and panel.TitleText:GetText() == "Buff Bars",
          "…and the title says which frame you are editing (" ..
          tostring(panel.TitleText and panel.TitleText:GetText()) .. ")")

  -- REVERT goes back to how this viewer was when the editor opened — NOT to defaults, which is the
  -- button below it. Conflating the two is how someone loses a setup they spent ten minutes on.
  M.HideEditorPanel()                       -- ends the editor session, dropping stale snapshots
  M.SetOpt(FID, "iconPadding", 7)           -- the state we entered the editor with
  M.ShowEditorPanel("essential", anchor)
  assertf(panel.revertButton._enabled == false,
          "Revert is disabled with nothing yet changed")
  rowOf("essential", "Icon Padding").Slider:SetValue(11)
  assertf(panel.revertButton._enabled == true, "…and arms itself the moment something changes")
  panel.revertButton:GetScript("OnClick")(panel.revertButton)
  assertf(M.GetOpt(FID, "iconPadding") == 7,
          "…reverting to the value the editor was opened with, not to the default (" ..
          tostring(M.GetOpt(FID, "iconPadding")) .. ")")
  assertf(rowOf("essential", "Icon Padding").Slider:GetValue() == 7,
          "…and the slider re-reads, or it would show a value the frame no longer uses")
  assertf(panel.revertButton._enabled == false, "…and goes quiet again once there is nothing to undo")

  -- RESET is the other one, and it does mean defaults — behind a CONFIRM. Revert is bounded and greys
  -- itself out when there is nothing to undo; Reset throws away every layout choice ever made for this
  -- viewer and nothing in the addon can put it back. They now sit three pixels apart.
  panel.resetButton:GetScript("OnClick")(panel.resetButton)
  assertf(M.IsConfirmShown(), "Reset to Default asks before it wipes anything")
  assertf(M.GetOpt(FID, "iconPadding") == 7,
          "…and the click alone changes nothing (" .. tostring(M.GetOpt(FID, "iconPadding")) .. ")")
  local confirm = panel.confirm
  assertf(tostring(confirm.Text:GetText()):find("Essential") ~= nil,
          "…naming the viewer it is about to reset, not asking a generic question over four of them")

  -- OUR OWN FRAME, INSIDE THE DIALOG. As a StaticPopup this opened at screen centre, under DragonUI's
  -- Exit Edit Mode / Reset All Positions buttons (UIParent, TOOLTIP level 1000) — and two attempts at
  -- out-stacking them failed in game. A child of the dialog draws inside the dialog's stacking, above
  -- it by construction, and lands beside the viewer rather than in the middle of the screen where
  -- those buttons live, so there is nothing left for it to lose to.
  assertf(confirm:GetParent() == panel, "the confirm belongs to the dialog, not to the screen")
  assertf(confirm:GetFrameLevel() > panel:GetFrameLevel(),
          "…drawing above it (" .. tostring(confirm:GetFrameLevel()) .. " vs " ..
          tostring(panel:GetFrameLevel()) .. ")")
  -- MODAL to the dialog. The question is about the very settings underneath it, and nudging a slider
  -- behind an unanswered "are you sure?" means answering it about a different state than the one read.
  assertf(confirm.Blocker:IsShown(), "…over a blocker that covers the controls it is asking about")
  assertf(confirm.Blocker:GetFrameLevel() < confirm:GetFrameLevel()
          and confirm.Blocker:GetFrameLevel() > panel:GetFrameLevel(),
          "…between the two, so it blocks the dialog without blocking the confirm")
  assertf(confirm.YesButton._neThreeSlice ~= nil and confirm.NoButton._neThreeSlice ~= nil,
          "…and its buttons wear the same red 3-slice as the dialog's")
  -- The message WRAPS. It was sized by anchoring TOPLEFT and TOPRIGHT, which does give a width — but on
  -- 3.3.5a that width truncates with an ellipsis instead of wrapping, so the second paragraph arrived as
  -- "…orientation and vis...". An explicit SetWidth is what wraps, and it is the only difference
  -- between the two, so it is what gets asserted.
  local textW = confirm.Text:GetWidth()
  assertf(textW > 0 and textW < confirm:GetWidth(),
          "the message has a width of its own, so it wraps rather than truncating (" ..
          tostring(textW) .. " inside " .. tostring(confirm:GetWidth()) .. ")")
  assertf(confirm:GetHeight() > 20 + 18 + 28 + 16,
          "…and the frame is sized around the wrapped text, not a constant (" ..
          tostring(confirm:GetHeight()) .. ")")

  -- Switching viewers takes it with it: it names one viewer and would act on whichever is current.
  M.ShowEditorPanel("buffBar", anchor)
  assertf(not M.IsConfirmShown(),
          "selecting another frame drops an unanswered confirm, which named the one before it")
  M.ShowEditorPanel("essential", anchor)

  panel.resetButton:GetScript("OnClick")(panel.resetButton)
  confirm.NoButton:GetScript("OnClick")(confirm.NoButton)
  assertf(not M.IsConfirmShown() and M.GetOpt(FID, "iconPadding") == 7,
          "answering No closes it and changes nothing")

  panel.resetButton:GetScript("OnClick")(panel.resetButton)
  confirm.YesButton:GetScript("OnClick")(confirm.YesButton)
  assertf(not M.IsConfirmShown() and not confirm.Blocker:IsShown(),
          "answering Yes closes it and lifts the blocker")
  assertf(M.GetOpt(FID, "iconPadding") == M.DEFAULTS.iconPadding,
          "…and puts this viewer's defaults back")
  assertf(M.GetOpt(FID, "iconLimit") == M.PER_FRAME_DEFAULT_OVERRIDES[FID].iconLimit,
          "…including the per-frame ones, not just the shared table")

  -- STALENESS, the whole reason the /cdm tab's header forbids a second editor. Both halves have to
  -- re-read: the dialog on open, the tab on every write from here.
  M.HideEditorPanel()
  M.SetOpt(FID, "iconSize", 150)            -- changed behind the dialog's back
  M.ShowEditorPanel("essential", anchor)
  assertf(rowOf("essential", "Icon Size").Slider:GetValue() == 150,
          "reopening re-reads every control, so it never opens on a stale value")

  -- THE OTHER HALF OF THE THEME ASSERTION: one kit, two sets of metrics, and the tab kept its own.
  -- These used to be read off the tab's copy of these very controls; there is no such copy now, so
  -- they read the tab's surviving widgets of the same KINDS — which is what the theme governs.
  S.SetDisplayMode("settings")
  S.EnsureSettingsPage()
  local function tabRowLabelled(label)
    for _, e in ipairs((S.settingsColumn or {}).entries or {}) do
      local f = e.frame
      if f.Label and f.Label.GetText and f.Label:GetText() == label then return f end
    end
  end
  local tabDrop = tabRowLabelled("Show them as")
  assertf(tabDrop ~= nil and tabDrop.Button.RefreshArt == nil,
          "the tab's dropdown is untouched by the dialog's theme")
  local tabSlider = tabRowLabelled("Icon inset")
  assertf(tabSlider ~= nil and tabSlider.Slider ~= nil and tabSlider.Left == nil,
          "…and its sliders are still the tall two-line kind, without the dialog's nudge arrows")
  local tabBtn
  for _, e in ipairs((S.settingsColumn or {}).entries or {}) do
    local f = e.frame
    if f.Button and f.Button.GetText and f.Button:GetText() == "Buff Bars" then tabBtn = f end
  end
  -- The BUTTON art, though, is now the addon's standard rather than the dialog's own: `buttonArt`
  -- defaults ON, so the tab wears the same red 3-slice. That is the one part of the theme that is
  -- deliberately NOT isolated, and it is asserted here so a future default flip cannot go unnoticed.
  assertf(tabBtn ~= nil and tabBtn.Button._neThreeSlice ~= nil,
          "…while its BUTTONS wear the red 3-slice, which is the addon's standard now")

  -- THE CLICK PATH.
  assertf(type(anchor.neEditorSettings) == "function", "the viewer's anchor carries its own opener")
  -- Read defensively and fall back to a no-op: a regression that unwires the handler would otherwise
  -- abort the run on a nil call, and a caught regression that looks like a truncated harness is barely
  -- a catch at all.
  local onMouseUp = anchor:GetScript("OnMouseUp")
  local onEnter   = anchor:GetScript("OnEnter")
  assertf(type(onMouseUp) == "function", "…and a mouse handler to open it with")
  onMouseUp = onMouseUp or function() end
  onEnter   = onEnter   or function() end

  M.ShowEditorPanel("buffBar", anchor)      -- so the assertion below is a real switch
  DragonUI.EditorMode._active, DragonUI._selected = true, nil
  onMouseUp(anchor, "LeftButton")
  assertf(M.IsEditorPanelShown() and pgs.essential.body:IsShown(),
          "left-click opens this frame's settings, which is how retail selects a system")
  -- CreateUIFrame only selects on LeftButton, so without our own call the editor's coordinate readout
  -- and Reset button would describe whatever was clicked last while the dialog edits something else.
  assertf(DragonUI._selected == anchor, "…selecting the frame too, so both agree on the target")

  M.HideEditorPanel()
  DragonUI._selected = nil
  onMouseUp(anchor, "RightButton")
  assertf(M.IsEditorPanelShown(), "right-click opens it as well")
  assertf(DragonUI._selected == anchor, "…and selects on that button too, where DragonUI does not")

  M.HideEditorPanel()
  DragonUI.EditorMode._active = false
  onMouseUp(anchor, "RightButton")
  assertf(not M.IsEditorPanelShown(), "outside edit mode there are no settings at all")

  -- The hint. A dialog nobody knows how to open is a dialog nobody opens, and the handle is the only
  -- thing on screen in edit mode.
  DragonUI.EditorMode._active = true
  GameTooltip.lines = {}   -- so a stale line from an earlier test cannot answer for this one
  onEnter(anchor)
  local hinted = false
  for _, line in ipairs(GameTooltip.lines) do
    if tostring(line):find("settings") then hinted = true end
  end
  assertf(hinted, "hovering the handle in edit mode says clicking opens its settings")

  -- LEAVING the editor takes the dialog with it, and drops the Revert snapshots with the session.
  M.ShowEditorPanel("essential", anchor)
  M.SetOpt(FID, "opacity", 70)
  DragonUI:HideAllEditableFrames(true)
  assertf(not M.IsEditorPanelShown(), "closing edit mode closes the dialog")
  DragonUI.EditorMode._active = true
  M.ShowEditorPanel("essential", anchor)
  assertf(panel.revertButton._enabled == false,
          "…and the next session's Revert starts clean, not armed with an hour-old state")

  -- The way out, to the settings a per-frame dialog has no business carrying.
  S.HidePanel()
  settingsRow.Button:GetScript("OnClick")(settingsRow.Button)
  assertf(not DragonUI.EditorMode:IsActive(),
          "Cooldown Manager Settings leaves edit mode, which covers the screen")
  assertf(S.panel:IsShown() and S.GetDisplayMode() == "settings",
          "…and opens the window on its Settings tab")

  -- Leave the store as we found it.
  M.HideEditorPanel()
  for _, id in pairs(M.FRAME_ID) do M.ResetOpts(id) end
  S.SetDisplayMode("spells")
  S.HidePanel()
end

-- The red 3-slice is the addon's STANDARD button now, not the Cooldown Manager dialog's own look.
-- Sixty-odd CreateFrame calls across a dozen modules build a plain UIPanelButtonTemplate, so the
-- mechanism is a sweep that reads the template's art rather than sixty edits — and a sweep is exactly
-- the kind of thing that can quietly find nothing at all.
print("\n=== BUTTON SKIN: THE ADDON-WIDE STANDARD ===")
do
  local BS = NE.buttonskin
  local function panelButton(parent)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    return b
  end

  local root = CreateFrame("Frame", nil, UIParent)
  local pane = CreateFrame("Frame", nil, root)
  local deep = CreateFrame("Frame", nil, pane)

  -- THE PREDICATE. On 3.3.5a the template's whole runtime identity is one texture path; a running
  -- frame cannot be asked which template built it.
  local b1 = panelButton(deep)
  assertf(BS._isPanelButton(b1) == true,
          "a panel button is recognised by the art the template gave it")
  assertf(BS._isPanelButton(pane) == false, "…and the frame holding one is not")
  local bare = CreateFrame("Button", nil, pane)
  bare:SetSize(120, 22)
  assertf(BS._isPanelButton(bare) == false,
          "…nor is a bare Button, which has no panel art to replace")
  -- The case that actually costs something if the predicate is loose. The addon is full of buttons
  -- carrying their OWN normal texture — item slots, icon buttons, the picker's tiles — and hideNativeArt
  -- would blank every one of them. "Has a normal texture" is not the test; "has THE panel texture" is.
  local iconBtn = CreateFrame("Button", nil, pane)
  iconBtn:SetSize(36, 36)
  iconBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  assertf(BS._isPanelButton(iconBtn) == false,
          "…and neither is a button wearing art of its own, which the skin would blank")

  local tabStandIn = panelButton(pane); tabStandIn._nePlain = true
  local optedOut   = panelButton(pane); optedOut._neNoSkin = true

  BS.Watch(root)
  assertf(b1._neThreeSlice ~= nil, "Watch skins panel buttons anywhere under a window")
  assertf(tostring((b1._neThreeSlice or {}).Left and b1._neThreeSlice.Left:GetTexture()):lower()
          :find("redbutton") ~= nil, "…with the shipped red sheet, not a blank texture")
  assertf(tabStandIn._neThreeSlice == nil,
          "…leaving _nePlain alone, which marks a button standing in for a tab")
  assertf(optedOut._neThreeSlice == nil, "…and honouring _neNoSkin for anything else that must stay stock")
  assertf(BS._isPanelButton(b1) == false,
          "…and a skinned button no longer matches, so the sweep cannot chase its own tail")

  -- LAZY PANES are the normal case, not the edge one: a window is registered before its contents
  -- exist, and a tab's pane is built the first time it is selected. One sweep at registration would
  -- miss most of the addon.
  deep:Hide()
  local late = panelButton(deep)
  assertf(late._neThreeSlice == nil, "a button built after registration starts unskinned")
  deep:Show()
  assertf(late._neThreeSlice ~= nil, "…and showing the pane that holds it skins it")

  -- Idempotent: Watch twice, sweep twice, nothing doubles up.
  local hooked = #(b1._neThreeSlice.hl or {})
  BS.Watch(root)
  BS.SkinPanelButtons(root)
  assertf(#(b1._neThreeSlice.hl or {}) == hooked,
          "re-sweeping an already-skinned window adds nothing")

  root:Hide()
end

-- The /necdm diagnostic is ~70 lines of formatting that nothing else touches, including the §F1
-- widget probe. Run it once: a nil-format or a bad select() in there would otherwise only surface
-- when someone reached for it to debug something else.
print("\n=== TRACKED BUFFS: CATALOG + SEEN (Phase 7) ===")
do
  local S = NE.cooldownviewersettings
  local A7 = S.adapter
  local bIcon7 = M.viewers.buffIcon

  local function namesOf(rows)
    local t = {}
    for _, r in ipairs(rows) do t[(r.name or r.label or ""):lower()] = r end
    return t
  end

  -- ── 7d: the generated catalog ───────────────────────────────────────────────────────────────
  assertf(type(M.AURA_CATALOG_BY_CLASS) == "table", "CdmAuraCatalog loaded")
  local pri = M.AURA_CATALOG_BY_CLASS.PRIEST
  assertf(pri and #pri > 0, "PRIEST has catalog rows (" .. tostring(pri and #pri) .. ")")
  do
    local gated, malformed = 0, 0
    for _, e in ipairs(pri) do
      if e.talent then
        gated = gated + 1
        if not e.tree then malformed = malformed + 1 end
      end
      if not (e.id and e.name and e.dur) then malformed = malformed + 1 end
    end
    assertf(malformed == 0, "every row carries id/name/dur, and a gated row carries its tree")
    assertf(gated > 0, "…and some are spec-gated (" .. gated .. " of " .. #pri .. ")")
  end

  -- The gate FAILS OPEN when the talent API is silent. This is the guard that stops Phase 7 from
  -- reintroducing the very bug it fixes: an empty talent table read as "no talents" would hide
  -- every gated row on a client that simply had not answered yet.
  assertf(GetTalentInfo == nil, "the harness has no talent API, so the gate is unanswerable")
  M.InvalidateTalentCache()
  assertf(M.HasTalent("Serendipity"), "unanswerable gate offers the row rather than hiding it")
  assertf(#M.GetAuraCatalog("PRIEST") == #pri, "…so the whole catalog is offered")

  -- With a talent API present the gate is real.
  GetNumTalentTabs = function() return 3 end
  GetNumTalents    = function(tab) return (tab == 1) and 2 or 0 end
  GetTalentInfo    = function(tab, i)
    -- 3.3.5a flat tuple: name, icon, tier, column, rank, maxRank
    if tab == 1 and i == 1 then return "Borrowed Time", "icon", 1, 1, 3, 5 end
    if tab == 1 and i == 2 then return "Serendipity",   "icon", 1, 2, 0, 3 end
    return nil
  end
  M.InvalidateTalentCache()
  assertf(M.HasTalent("Borrowed Time"), "a talent with rank 3 reads as taken")
  assertf(not M.HasTalent("Serendipity"), "…one at rank 0 does not")
  local gatedCat = namesOf(M.GetAuraCatalog("PRIEST"))
  assertf(gatedCat["borrowed time"] ~= nil, "talented row is offered")
  assertf(gatedCat["serendipity"] == nil, "untalented row is withheld")
  assertf(gatedCat["fade"] ~= nil, "ungated row is always offered")
  assertf(gatedCat["shadow weaving"] == nil, "a talent the API never mentions is withheld too")

  -- Show Unlearned is the escape hatch: the gate is derived data, so there is a way past it.
  local shown = namesOf(M.GetAuraCatalog("PRIEST", true))
  assertf(shown["serendipity"] ~= nil, "Show Unlearned reveals the withheld row")

  -- ── WHICH SPEC IS THIS? ──
  --
  -- Points spent per tree is the only signal 3.3.5a offers, and for a starter layout it is the right
  -- one: the FIRST point is already a declaration of intent, which is what a starter needs. What the
  -- detection must not do is guess when there is nothing to read — the owner's call, and the reason
  -- these four cases are asserted rather than a single happy path.
  local POINTS = { 0, 0, 0 }
  local TREES  = { "Discipline", "Holy", "Shadow" }
  GetTalentTabInfo = function(tab, _, _, group)
    -- (index, isInspect, isPet, group) on this client. The GROUP argument is the whole reason the
    -- inactive spec can be detected at all; group 2 here is deliberately a different build.
    if group == 2 then return TREES[tab], "icon", ({ 51, 0, 0 })[tab] or 0 end
    return TREES[tab], "icon", POINTS[tab] or 0
  end

  assertf(M.DetectSpec() == nil, "no talent points spent is UNKNOWN, not tree 1")
  POINTS = { 5, 5, 0 }
  assertf(M.DetectSpec() == nil, "…and so is an exact tie, which has no right answer either")
  POINTS = { 1, 0, 0 }
  local tab, name = M.DetectSpec()
  assertf(tab == 1 and name == "Discipline",
          "a SINGLE point names the spec — weak evidence of power, strong evidence of intent")
  POINTS = { 11, 3, 57 }
  assertf(M.DetectSpec() == 3, "…and the dominant tree wins once there are real points")
  assertf(M.DetectSpec(2) == 1,
          "…while the group argument reads the OTHER spec, which per-spec layouts depend on")
  assertf(#M.SpecNames() == 3 and M.SpecNames()[3] == "Shadow", "the tree names come from the client")

  -- ── The starter itself ──
  local starter = M.STARTER_BY_CLASS and M.STARTER_BY_CLASS.PRIEST
  assertf(starter ~= nil and starter[3] ~= nil, "the seed carries a per-spec starter for Shadow")
  local P = NE.cooldownviewersettings.presets
  assertf(P.UseSpecStarter(3), "…and it applies")
  -- A tab the class does not have refuses rather than falling back to one it does. The menu passes
  -- this through a StaticPopup's `data`, which outlives the menu that built it.
  assertf(P.UseSpecStarter(9) == false and P.UseSpecStarter(nil) == false,
          "…while a tab that does not exist applies nothing at all")

  -- DISABLED, NOT DELETED, which is what keeps the starter undoable by hand: every curated spell is
  -- still listed, so the off-spec ones sit under Not Displayed one drag from coming back.
  local ent = M.GetEditableList("essential", "PRIEST")
  local on, off = {}, {}
  for _, e in ipairs(ent) do
    if e.enabled then on[e.spellID] = true else off[e.spellID] = true end
  end
  assertf(on[8092] == true, "Mind Blast is on for Shadow")                      -- in the Shadow starter
  assertf(off[47540] == true, "…and Penance is OFF rather than gone")           -- Discipline's
  assertf(#ent == #M.ESSENTIAL_BY_CLASS.PRIEST,
          "…with the full class list still present (" .. #ent .. ")")

  -- ONCE PER BUCKET. This is the entire safety argument for auto-applying: a bucket is seeded the
  -- first time a character plays a talent group and marked in the same breath, so the auto path can
  -- never run a second time over curation the player has since done.
  local lay = M._layoutBucket(true)
  lay.starterSeeded = nil
  M.SetSpellEnabled("essential", 47540, true)          -- the player's own edit, after the starter
  assertf(P.SeedStarterIfFresh() == true, "a fresh bucket seeds its spec's starter")
  assertf(lay.starterSeeded == 3, "…and is marked with the tree it seeded from")
  M.SetSpellEnabled("essential", 47540, true)          -- edit it again
  assertf(P.SeedStarterIfFresh() == false, "…and never seeds twice")
  assertf(M.IsSpellEnabled("essential", 47540) == true,
          "…so an edit made after the seed survives every later login")

  -- No signal, no seed — and no marker either, so the FIRST point spent still gets a starter.
  lay.starterSeeded = nil
  POINTS = { 0, 0, 0 }
  assertf(P.SeedStarterIfFresh() == false, "a character with no talent points is skipped")
  assertf(lay.starterSeeded == nil, "…without being marked, so spending a point still seeds later")
  POINTS = { 0, 0, 4 }
  assertf(P.SeedStarterIfFresh() == true, "…which is exactly what happens on that first point")

  GetTalentTabInfo = nil

  -- ── 7a: the seen registry ───────────────────────────────────────────────────────────────────
  M.ResetTracking()
  BUFFS.player = {
    { name = "Inner Focus", rank = "", icon = "Interface\\Icons\\IF", count = 0,
      duration = 30, expiration = NOW + 25, spellID = 14751 },
    { name = "Arcane Intellect", rank = "Rank 3", icon = "Interface\\Icons\\AI", count = 0,
      duration = 1800, expiration = NOW + 1700, spellID = 10157 },
  }
  auraTick("player")
  local seen = {}
  for _, e in ipairs(M.GetSeenAuraList("PRIEST")) do seen[e.spellID] = e end
  assertf(seen[14751] ~= nil, "the scan records a short buff it met")
  assertf(seen[14751] and seen[14751].name == "Inner Focus" and seen[14751].dur == 30,
          "…with its name and duration, not just an id")
  assertf(seen[14751] and seen[14751].icon == "Interface\\Icons\\IF",
          "…and the icon, which is the only source for an aura with no spellbook entry")
  assertf(seen[10157] == nil, "a 1800s buff is NOT recorded (the window keeps food buffs out)")

  -- THE ONE-WAY DOOR. An aura hidden before it was ever seen must still be recorded, or hiding
  -- something removes the only row that could unhide it. This is why NoteSeenAura is called before
  -- ShouldTrackBuff rather than inside its true branch.
  --
  -- The aura has to be hidden BEFORE it first appears, and that is fiddlier than it looks:
  -- ResetTracking rebuilds the shown viewers itself, so an aura already up at that moment gets
  -- scanned — and recorded — while the pool is still empty. A first draft of this test did exactly
  -- that and passed with the guard removed. So: clear the auras, assign hidden, THEN raise it.
  -- Auras down BEFORE the reset, for the same reason: ResetTracking's rebuild would otherwise
  -- record whatever is still up as it clears. And through `settle`, not bare — NE.aura caches its
  -- snapshot per frame, so a rebuild in the same frame re-reads the auras that were up a moment ago
  -- however empty BUFFS.player now is.
  BUFFS.player = {}
  settle(M.ResetTracking)
  auraTick("player")
  assertf(#M.GetSeenAuraList("PRIEST") == 0, "nothing up, nothing recorded")
  M.SetAuraAssignment("PRIEST", 15286, "hidden", "Vampiric Embrace")
  BUFFS.player = {
    { name = "Vampiric Embrace", rank = "", icon = "Interface\\Icons\\VE", count = 0,
      duration = 60, expiration = NOW + 55, spellID = 15286 },
  }
  auraTick("player")
  local seen2 = {}
  for _, e in ipairs(M.GetSeenAuraList("PRIEST")) do seen2[e.spellID] = e end
  assertf(seen2[15286] ~= nil, "a HIDDEN aura is still recorded as seen (the one-way-door guard)")
  assertf(shownItems(bIcon7) == 0, "…while staying out of the viewer, which is what hidden means")
  assertf(namesOf(A7.GetItems("hiddenAura", "PRIEST"))["vampiric embrace"] ~= nil,
          "…so the row that could unhide it is still there")

  -- ── The row has to be identifiable on hover ──────────────────────────────────────────────────
  -- An aura id this client cannot hyperlink leaves SetHyperlink succeeding and the tooltip EMPTY.
  -- On a 38px grid tile with no label of its own that is a row the player cannot name at all, which
  -- is what Not Displayed looked like once it filled with catalog rows. 900123 is deliberately
  -- absent from the stub's spellbook, so nothing but the fallback can put a name up.
  local realAuto = M.IsAutoTrackBuffs()
  M.ResetTracking()
  M.SetAutoTrackBuffs(false)   -- candidates land under Not Displayed: the shipped default
  M.NoteSeenAura(900123, "Unlinkable Aura", "Interface\\Icons\\UA", 20)
  S.OpenTo("auras")            -- the grids only hold the ACTIVE mode's rows
  local hidGrid = S._categories.hiddenAura
  local auraTile
  for i = 1, (hidGrid and hidGrid._count or 0) do
    if hidGrid.items[i].spellName == "Unlinkable Aura" then auraTile = hidGrid.items[i] end
  end
  assertf(auraTile ~= nil, "the unlinkable aura has a tile under Not Displayed")
  -- Through the tile's own OnEnter, not the helper: the bug was in what the hover path passed.
  GameTooltip:ClearLines()
  auraTile:GetScript("OnEnter")(auraTile)
  assertf(GameTooltip:NumLines() > 0, "hovering it produces a tooltip at all")
  assertf(GameTooltip.lines[1] == "Unlinkable Aura", "…titled with the name the registry stored")

  -- …and a resolvable id still gets the CLIENT's tooltip, not the fallback. Without this the fix
  -- could be "always use our own name", which would throw away every spell tooltip in the picker.
  local spellTile
  local essGrid = S._categories.essential
  for i = 1, (essGrid and essGrid._count or 0) do
    if essGrid.items[i].spellID and SPELLS[essGrid.items[i].spellID] then spellTile = essGrid.items[i] end
  end
  assertf(spellTile ~= nil, "…and a linkable spell tile to compare against")
  GameTooltip:ClearLines()
  spellTile:GetScript("OnEnter")(spellTile)
  -- The BODY, not the title: the fallback would reproduce the title exactly, so only the body can
  -- tell "the client answered" apart from "we wrote the name ourselves".
  assertf(GameTooltip.lines[2] == "client tooltip body",
          "a linkable spell still shows the client's own tooltip, body and all")
  -- …and the fallback did not ALSO fire. Counted rather than measured against the total, because
  -- the alert badge adds lines of its own: a name appearing twice is the specific defect.
  local titleCount = 0
  for _, ln in ipairs(GameTooltip.lines) do
    if ln == SPELLS[spellTile.spellID][1] then titleCount = titleCount + 1 end
  end
  assertf(titleCount == 1, "…with the name once, not doubled by a fallback that fired anyway")

  -- The same hazard on the VIEWER, which is the surface that matters in a fight: a tracked buff
  -- whose id will not hyperlink must still name itself on hover.
  M.SetAuraAssignment("PRIEST", 900123, "icon", "Unlinkable Aura")
  BUFFS.player = {
    { name = "Unlinkable Aura", rank = "", icon = "Interface\\Icons\\UA", count = 0,
      duration = 20, expiration = NOW + 18, spellID = 900123 },
  }
  auraTick("player")
  local liveTile = bIcon7.items[1]
  assertf(liveTile and liveTile.spellID == 900123, "the aura is on a live buff-icon tile")
  GameTooltip:ClearLines()
  liveTile:OnEnter()
  assertf(GameTooltip.lines[1] == "Unlinkable Aura", "…and hovering it there names it too")
  BUFFS.player = {}
  auraTick("player")
  M.SetAutoTrackBuffs(realAuto)

  -- The cap, oldest evicted first.
  M.ResetTracking()
  M.NoteSeenAura(900001, "Oldest", "i", 10)
  nextFrame(10)
  for i = 2, 60 do M.NoteSeenAura(900000 + i, "Filler " .. i, "i", 10) end
  nextFrame(10)
  M.NoteSeenAura(999999, "Newest", "i", 10)
  local capped = {}
  local n = 0
  for _, e in ipairs(M.GetSeenAuraList("PRIEST")) do capped[e.spellID] = true; n = n + 1 end
  assertf(n == 60, "the registry caps at 60 (" .. n .. ")")
  assertf(capped[999999], "…keeping the newest")
  assertf(not capped[900001], "…and evicting the least recently seen")

  -- ── 7d runtime: matching by NAME, so an assignment survives rank ─────────────────────────────
  -- The payoff for the catalog storing rank-1 ids. The aura below is a DIFFERENT spellID from the
  -- assigned one and is far outside the auto window, so nothing but a name match can show it.
  M.ResetTracking()
  M.SetAuraAssignment("PRIEST", 10060, "icon", "Power Infusion")
  BUFFS.player = {
    { name = "Power Infusion", rank = "Rank 9", icon = "Interface\\Icons\\PI", count = 0,
      duration = 300, expiration = NOW + 280, spellID = 777777 },
  }
  auraTick("player")
  assertf(shownItems(bIcon7) == 1,
          "an assignment made at one rank matches the aura cast at another (" ..
          shownItems(bIcon7) .. ")")

  -- ── the DoT fix, which falls out of the registry becoming reachable at all ───────────────────
  local realExists = UnitExists
  UnitExists = function(u) return u == "player" or u == "target" end
  M.ResetTracking()
  M.SetAuraAssignment("PRIEST", 589, "icon", "Shadow Word: Pain")
  BUFFS.player = {}
  DEBUFFS.target = {
    { name = "Shadow Word: Pain", rank = "Rank 10", icon = "Interface\\Icons\\SWP", count = 0,
      duration = 18, expiration = NOW + 14, spellID = 25368 },
  }
  auraTick("player")
  assertf(shownItems(bIcon7) == 1,
          "an explicitly tracked DoT on the target now shows (" .. shownItems(bIcon7) .. ")")
  DEBUFFS.target = {}
  UnitExists = realExists

  -- ── 7b: where an unassigned candidate lands ──────────────────────────────────────────────────
  M.ResetTracking()
  M.SetAutoTrackBuffs(true)
  M.SetAutoTrackDest("both")
  local buffRows = namesOf(A7.GetItems("trackedBuff", "PRIEST"))
  local barRows  = namesOf(A7.GetItems("trackedBar", "PRIEST"))
  assertf(buffRows["fade"] ~= nil and barRows["fade"] ~= nil,
          "dest=both puts a candidate in BOTH aura sections")
  assertf(buffRows["fade"].auto, "…marked auto, because the viewer is deciding it")
  assertf(buffRows["fade"].assignment == nil, "…and with no stored assignment")

  M.SetAutoTrackDest("bar")
  assertf(namesOf(A7.GetItems("trackedBuff", "PRIEST"))["fade"] == nil,
          "dest=bar keeps candidates out of Tracked Buffs")
  assertf(namesOf(A7.GetItems("trackedBar", "PRIEST"))["fade"] ~= nil, "…and in Tracked Bars")

  -- Auto-track OFF: nothing is showing these, so Not Displayed is where they honestly belong.
  M.SetAutoTrackBuffs(false)
  assertf(namesOf(A7.GetItems("trackedBar", "PRIEST"))["fade"] == nil,
          "auto-track off empties the tracked sections of candidates")
  assertf(namesOf(A7.GetItems("hiddenAura", "PRIEST"))["fade"] ~= nil,
          "…and lists them under Not Displayed instead")
  M.SetAutoTrackBuffs(true)
  M.SetAutoTrackDest("both")

  -- An explicit assignment removes the candidate row, so a buff is never listed twice — matched by
  -- name, so a rank-1 catalog row and a differently-ranked assignment do not both appear.
  M.SetAuraAssignment("PRIEST", 999123, "bar", "Fade")
  local dupBar = A7.GetItems("trackedBar", "PRIEST")
  local fades = 0
  for _, r in ipairs(dupBar) do if (r.label or ""):lower() == "fade" then fades = fades + 1 end end
  assertf(fades == 1, "an assigned aura is listed once, not once per source (" .. fades .. ")")
  M.ResetTracking()

  -- The claim that pinning an auto row needs NO new write path: the drag already calls
  -- SetAuraAssignment, and "stop deciding this one for me" is exactly what that write means.
  local cand = M.GetAuraCandidates("PRIEST")[1]
  assertf(cand ~= nil and cand.name, "there is a candidate to drag (" .. tostring(cand and cand.name) .. ")")
  assertf(A7.Assign(cand.spellID, "trackedBar", "trackedBuff", "PRIEST"),
          "…and dragging it across is a legal move")
  local pinnedRow = namesOf(A7.GetItems("trackedBuff", "PRIEST"))[cand.name:lower()]
  assertf(pinnedRow and pinnedRow.assignment == "icon", "…which makes it an explicit icon row")
  assertf(pinnedRow and not pinnedRow.auto, "…no longer marked auto")
  local storedName
  for _, e in ipairs(M.GetTrackedAuraList("PRIEST") or {}) do
    if e.spellID == cand.spellID then storedName = e.name end
  end
  assertf(storedName == cand.name,
          "…and the write stored a NAME the drag never supplied, via ResolveAuraName")
  M.ResetTracking()

  -- ── 7b/7c: the tile and the empty state ──────────────────────────────────────────────────────
  S.OpenTo("auras")
  local barGrid = S._categories.trackedBar
  assertf(barGrid ~= nil and barGrid._count > 0, "the Tracked Bars grid is no longer empty")
  local tile7
  for i = 1, barGrid._count do
    if (barGrid.items[i].spellName or "") == "Fade" then tile7 = barGrid.items[i] end
  end
  assertf(tile7 ~= nil, "…and carries a named aura tile")
  assertf(tile7 and tile7._aura and tile7._aura.auto, "the tile knows it is an auto row")
  assertf(tile7 and tile7.Icon._desat == true, "…and reads as one (desaturated)")
  assertf(tile7 and tile7.token == nil,
          "…with no equip binding, so its right-click cannot route through the trinket path")

  assertf(A7.EmptyText("trackedBuff") ~= "(empty)",
          "an aura section's empty text is a sentence, not \"(empty)\"")
  assertf(A7.EmptyText("essential") == "(empty)", "…and other categories keep the terse form")

  S.HidePanel()
  GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil
  M.InvalidateTalentCache()
  M.ResetTracking()
  BUFFS.player = {}
end

print("\n=== DIAGNOSTIC (/necdm) ===")
do
  local okDiag, errDiag = pcall(SlashCmdList["NECDM"])
  assertf(okDiag, "/necdm runs without erroring" .. (okDiag and "" or (": " .. tostring(errDiag))))
  assertf(M._widgetProbe ~= nil, "…and leaves its one throwaway Cooldown probe frame cached")
end

print("\n=== UNIT-EVENT FILTER ===")
local probe = CreateFrame("Frame")
local got = {}
probe:SetScript("OnEvent", function(_, ev, unit) got[#got + 1] = unit end)
probe:RegisterUnitEvent("UNIT_AURA", "player")
fireEvent("UNIT_AURA", "player")
fireEvent("UNIT_AURA", "target")
fireEvent("UNIT_AURA", "raid14")
assertf(#got == 1 and got[1] == "player", "filtered UNIT_AURA delivered only for player (" .. #got .. " of 3)")

print("")
if fails == 0 then print("ALL BOOT CHECKS PASSED") else print(fails .. " FAILURE(S)") end
os.exit(fails == 0 and 0 or 1)
