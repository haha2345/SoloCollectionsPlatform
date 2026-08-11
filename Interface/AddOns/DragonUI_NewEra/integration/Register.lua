-- DragonUI_NewEra/integration/Register.lua
-- The single DragonUI handshake every NewEra panel module routes through.
--
-- Later-sprint panels NEVER touch DragonUI internals directly. They call
--   NE.RegisterPanel(spec)
-- and this file wires that spec into DragonUI's ModuleRegistry, MoversSystem,
-- and our own boot dispatcher + QA harness + options list. Every base-API call
-- is defensively guarded so a missing/renamed base symbol logs a warning instead
-- of erroring (load order between the parallel-built addon parts must never crash).
--
-- DOWNPORT: this whole file is new glue (no 1.15 NewEra counterpart); the 1.15
-- addon had its own settings UI, here we proxy into DragonUI's unified UX.

local NE = DragonUI_NewEra
if not NE then return end

-- ----------------------------------------------------------------------------
-- Small logging helper. Prefer DragonUI's :Print / :Error if present, else
-- fall back to DEFAULT_CHAT_FRAME so a missing base API still surfaces.
-- ----------------------------------------------------------------------------
local function warn(msg)
    local dragon = NE.dragon
    if dragon and type(dragon.Error) == "function" then
        -- DragonUI:Error(...) is a method (self-call).
        local ok = pcall(dragon.Error, dragon, "[NewEra] " .. msg)
        if ok then return end
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r: " .. msg)
    end
end
NE._warn = NE._warn or warn

-- The ordered list the Options builder renders one toggle per panel from.
-- Each entry: { id, title, desc, refresh, order }. Kept here (not in Options.lua)
-- so it is populated even if DragonUI_Options never loads.
NE.optionPanels = NE.optionPanels or {}

-- ----------------------------------------------------------------------------
-- DB bootstrap. Panel ENABLE flags + the per-panel `enabled` toggles live in
-- DragonUI's profile (DragonUIDB) under profile.modules.ne_* so the whole UX
-- has exactly one enable-state owner. profile.newera holds panel-internal state only.
-- ----------------------------------------------------------------------------
local function ensureProfile()
    local dragon = NE.dragon
    if not (dragon and dragon.db and dragon.db.profile) then
        return nil
    end
    local profile = dragon.db.profile
    if type(profile.newera) ~= "table" then
        profile.newera = { enabled = true }
    end
    if profile.newera.enabled == nil then
        profile.newera.enabled = true
    end
    return profile.newera
end
NE.EnsureProfile = ensureProfile

-- Convenience: the newera config sub-table (may be nil pre-login).
function NE.Config()
    return ensureProfile()
end

-- ----------------------------------------------------------------------------
-- NE.OnReady — bootstrap.lua calls this once SavedVariables are loaded
-- (after ADDON_LOADED for our addon, i.e. DragonUI.db is already an AceDB).
-- ----------------------------------------------------------------------------
function NE.OnReady()
    local cfg = ensureProfile()
    if not cfg then
        warn("DragonUI.db.profile not available at OnReady; newera settings not initialised.")
        return
    end

    -- Re-run boot for any panel that registered BEFORE OnReady (load-order
    -- safety: a panel file may have called RegisterPanel before SavedVariables
    -- were ready, so its modules.Register entry now has a real default to read).
    local modules = NE.modules and NE.modules._dragonModulesTable and NE.modules._dragonModulesTable(true)
    for _, panel in ipairs(NE.optionPanels) do
        local key = NE.modules and NE.modules.CanonicalName and NE.modules.CanonicalName(panel.id) or ("ne_" .. panel.id)
        if modules and (modules[key] == nil or type(modules[key]) ~= "table") then
            modules[key] = { enabled = true }
        end
    end
end

-- ----------------------------------------------------------------------------
-- NE.RegisterPanel(spec)
--   spec = { id, title, desc, frame, openFn, closeFn, defaultPoint, order }
--
-- The one helper every panel module calls. Wires the panel into:
--   (1) profile.modules["ne_"..id] = { enabled = true }   (default)
--   (2) NE.modules.Register  (our boot dispatcher, from Core agent)
--   (3) NE.dragon.ModuleRegistry:Register  (DragonUI's module list)
--   (4) NE.dragon.MoversSystem:RegisterMover  (legacy; removed from DragonUI — skipped when absent)
--   (5) NE.qa.modules  (the /dnetest harness)
--   (6) NE.optionPanels  (the "New Era" options tab)
-- Every step is independently guarded.
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- NE.RegisterHUDFrame(spec)
--   spec = { name, frame, section, key, editorVisible, showTest, hideTest, onHide,
--            perCharacter, editorSettings, editorTip }
--
-- The HUD-frame counterpart to RegisterPanel. RegisterPanel is for toggled WINDOWS, which drag by
-- their own title bar and persist through NE.FrameUtil.PersistWindowPosition.
--
-- It is the WRONG seam for an always-on HUD element. DragonUI historically had TWO independent
-- positioning systems and `/dui edit` only ever drove one of them:
--
--   addon.MoversSystem   (core/movers.lua)  -- what RegisterPanel wired. Its ToggleConfigMode was
--                                              reachable only from a dead `elseif` branch in
--                                              core/commands.lua (addon.EditorMode always exists,
--                                              so the first branch always won). Now DELETED from
--                                              DragonUI outright — core/movers.lua is no longer in
--                                              core/core.xml's load list.
--   addon.EditableFrames (core/api.lua)     -- what /dui edit actually shows, via
--                                              EditorMode:Show -> addon:ShowAllEditableFrames.
--                                              The only surviving system, and the one this uses.
--
-- So a HUD frame must register as an EditableFrame or it is simply invisible to edit mode.
--
-- Position round-trip: DragonUI's editor saves via addon.SaveUIFramePosition, which writes
-- `anchor` / `posX` / `posY` into profile[section][key]. Note that its own
-- addon.ApplyUIFramePosition reads DIFFERENT field names (`x`/`y`, gated on an `override` flag
-- nothing sets), so it will not restore what Save wrote — we therefore restore ourselves, reading
-- the fields Save actually writes. This mirrors what MoversSystem:LoadPosition does for the same
-- legacy configPath shape (core/movers.lua:358-366).
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- NE.FramePositionKey(key, perCharacter) -> the profile key a HUD frame's position is stored under.
--
-- DragonUI's profile is shared across characters — that is what makes its class-keyed stores work at
-- all — so a position saved under a bare key is a position every character on the account shares.
-- For a HUD element that is often right (a unit frame belongs where you like unit frames); for the
-- Cooldown Manager viewers it is not, because what a Priest wants tracked and where a Warlock wants
-- it are different questions and the answer to the second follows the first.
--
-- Done by KEY rather than by a parallel store, because the key is the ONLY thing DragonUI's editor
-- takes from us: it reads and writes profile[section][key] itself through configPath. Varying the key
-- therefore buys per-character positions with no change to DragonUI at all (CONTRACTS §0).
--
-- Falls back to the shared key when the client cannot yet name the player. A shared position is a
-- mild surprise; a position filed under "-nil" is one nothing will ever read back.
function NE.FramePositionKey(key, perCharacter)
    if not (key and perCharacter) then return key end
    local name = UnitName and UnitName("player")
    if not name or name == "" then return key end
    local realm = GetRealmName and GetRealmName()
    if realm and realm ~= "" then return key .. "-" .. name .. "-" .. realm end
    return key .. "-" .. name
end

-- Seed a per-character position slot from the shared one, once.
--
-- A character upgrading into per-character positions must not watch its viewers jump back to the
-- default — that reads as data loss, not as a feature. The shared entry is deliberately LEFT IN
-- PLACE: every other character still needs it as their own seed, and deleting it would hand the
-- upgrade to whoever logged in first and a default layout to everybody else.
local function seedPerCharacterPosition(section, sharedKey, key)
    if key == sharedKey then return end
    local dragon = NE.dragon
    local profile = dragon and dragon.db and dragon.db.profile
    local sect = profile and profile[section]
    if not (sect and sect[sharedKey]) or sect[key] then return end
    local copy = {}
    for k, v in pairs(sect[sharedKey]) do copy[k] = v end
    sect[key] = copy
end

function NE.ApplySavedFramePosition(frame, section, key)
    local dragon = NE.dragon
    local profile = dragon and dragon.db and dragon.db.profile
    local cfg = profile and profile[section] and profile[section][key]
    if not (frame and cfg and cfg.anchor and cfg.posX and cfg.posY) then return false end
    frame:ClearAllPoints()
    frame:SetPoint(cfg.anchor, UIParent, cfg.anchor, cfg.posX, cfg.posY)
    return true
end

-- ----------------------------------------------------------------------------
-- NE.OpenFrameEditor(frame) -> true | false, reason
--
-- Enter DragonUI's editor mode, with one frame pre-selected. This is the seam a module uses to offer
-- "go position this thing" from inside its own window, and it exists here rather than in the module
-- for CONTRACTS §4: panel modules never reach into DragonUI internals directly.
--
-- THE ARGUMENT IS THE CONTENT FRAME, and the anchor is what gets selected. RegisterHUDFrame registers
-- the CreateUIFrame anchor as the editable frame and hangs the content off it (see the note below), so
-- the editor knows the anchor and nothing about the content. Handing SelectEditorFrame a content frame
-- would put the coordinate readout and the Reset button on a frame the editor cannot move, and it
-- would look like it worked. `.editorAnchor` is set by RegisterHUDFrame for exactly this.
--
-- Failure is a returned reason, not a print: the caller knows where its message belongs. In particular
-- EditorMode:Show() returns SILENTLY in combat (DragonUI modules/editor_mode.lua:334 — an empty
-- branch, no message), so a button wired straight to it would appear to do nothing at all mid-fight.
-- ----------------------------------------------------------------------------

function NE.OpenFrameEditor(frame)
    local dragon = NE.dragon
    local EM = dragon and dragon.EditorMode
    if not (EM and type(EM.Show) == "function" and type(EM.IsActive) == "function") then
        return false, "DragonUI's editor mode isn't available."
    end
    -- This check exists for the MESSAGE, not the behaviour: EditorMode:Show() already no-ops in
    -- combat, and the IsActive re-check below would catch it either way — but "editor mode declined to
    -- open" tells a player nothing, where "not during combat" tells them to try again in ten seconds.
    if InCombatLockdown and InCombatLockdown() then
        return false, "Editor mode can't be opened during combat."
    end

    if not EM:IsActive() then
        local ok, err = pcall(EM.Show, EM)
        if not ok then return false, "Editor mode failed to open: " .. tostring(err) end
    end
    -- Re-check rather than trusting the call, per the header.
    if not EM:IsActive() then
        return false, "Editor mode declined to open."
    end

    local target = frame and (frame.editorAnchor or frame) or nil
    if target and type(dragon.SelectEditorFrame) == "function" then
        pcall(dragon.SelectEditorFrame, target)
    end
    return true
end

-- ----------------------------------------------------------------------------
-- NE.CloseFrameEditor() -> true | false, reason
--
-- The other half of OpenFrameEditor, for a module that wants to hand the player back to its own
-- window. DragonUI's EditorMode:Hide saves every registered frame's position on the way out
-- (HideAllEditableFrames(true)), so leaving this way loses nothing.
-- ----------------------------------------------------------------------------
function NE.CloseFrameEditor()
    local dragon = NE.dragon
    local EM = dragon and dragon.EditorMode
    if not (EM and type(EM.Hide) == "function") then
        return false, "DragonUI's editor mode isn't available."
    end
    local ok, err = pcall(EM.Hide, EM)
    if not ok then return false, "Editor mode failed to close: " .. tostring(err) end
    return true
end

-- Is the editor open right now?
--
-- Defaults to TRUE when DragonUI exposes no way to ask, which is the safe answer rather than the
-- optimistic one: the only caller is a mouse handler on an editor anchor, and those anchors are
-- EnableMouse(false) until addon.HideUIFrame turns them on — which only ever happens from
-- ShowAllEditableFrames. No editor, no clicks to gate.
function NE.IsFrameEditorActive()
    local dragon = NE.dragon
    local EM = dragon and dragon.EditorMode
    if not (EM and type(EM.IsActive) == "function") then return true end
    local ok, active = pcall(EM.IsActive, EM)
    return (ok and active) and true or false
end

-- ----------------------------------------------------------------------------
-- NE.OpenFrameEditorSettings(anchor) -> true | false
--
-- Open the settings a HUD frame registered through `spec.editorSettings`. Retail puts a system's own
-- settings ON the frame in Edit Mode rather than in a separate options window, and this is that seam.
--
-- The field is a CALLBACK, not a menu or a panel: what a module opens when its frame is clicked is
-- the module's business, and this file's business is only deciding when it may (CONTRACTS §4). The
-- Cooldown Manager opens a dialog beside the frame; another module could open anything.
--
-- Selecting the frame first is deliberate, and matters most on right-click, which leaves DragonUI's
-- own selection alone (CreateUIFrame only selects on LeftButton) — without this the coordinate
-- readout and Reset button would still describe whatever was clicked last while the dialog edits
-- something else.
-- ----------------------------------------------------------------------------
function NE.OpenFrameEditorSettings(anchor)
    local open = anchor and anchor.neEditorSettings
    if type(open) ~= "function" then return false end
    if not NE.IsFrameEditorActive() then return false end

    local dragon = NE.dragon
    if dragon and type(dragon.SelectEditorFrame) == "function" then
        pcall(dragon.SelectEditorFrame, anchor)
    end
    local ok, err = pcall(open, anchor)
    if not ok then
        warn("editor settings failed to open: " .. tostring(err))
        return false
    end
    return true
end

-- Wire the click and its discoverability hint onto an editor anchor.
--
-- SetScript, not HookScript: CreateUIFrame sets OnMouseDown (left-click select), OnDragStart and
-- OnDragStop, and none of OnMouseUp / OnEnter / OnLeave — so nothing here overwrites base behaviour.
-- This is a runtime write to a frame we own, not an edit to DragonUI (CONTRACTS §0).
--
-- EITHER BUTTON opens it, because retail opens a system's dialog on SELECTION and left-click is what
-- selects. Left-click is also the drag, so this fires on the release that ends one too — which is
-- also the retail behaviour: the dialog for the thing you just moved stays with it.
local function attachEditorSettings(anchor, spec)
    anchor.neEditorSettings = spec.editorSettings

    anchor:SetScript("OnMouseUp", function(self)
        NE.OpenFrameEditorSettings(self)
    end)

    -- Settings nobody knows are there are settings nobody uses. The green handle is the only thing on
    -- screen in edit mode, so the hint goes on it.
    if spec.editorTip == false or not GameTooltip then return end
    anchor:SetScript("OnEnter", function(self)
        if not NE.IsFrameEditorActive() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.label or spec.name, 1, 1, 1)
        GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click for this frame's settings.", 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- RegisterEditableFrame on its own is ONLY metadata. The editor's drag affordances —
-- RegisterForDrag, OnDragStart/OnDragStop (which auto-saves to configPath), the green nineslice
-- overlay, the text label — are attached by DragonUI's frame FACTORY, addon.CreateUIFrame
-- (core/api.lua:255). addon.HideUIFrame, which the editor calls on each registered frame, only does
-- SetMovable(true)/EnableMouse(true) and shows an overlay that a plain CreateFrame doesn't have.
--
-- So the DragonUI pattern is: build a CreateUIFrame **anchor**, register the ANCHOR as the editable
-- frame, and hang the real HUD content off it. modules/castbar.lua does exactly this with
-- CastbarModule.anchor. We follow it.
function NE.RegisterHUDFrame(spec)
    if type(spec) ~= "table" or not (spec.name and spec.frame) then
        warn("RegisterHUDFrame needs a name and frame; ignored.")
        return
    end
    local dragon = NE.dragon
    if not (dragon and type(dragon.RegisterEditableFrame) == "function"
            and type(dragon.CreateUIFrame) == "function") then
        warn("DragonUI editor API absent; '" .. tostring(spec.name) .. "' won't be movable.")
        return
    end

    local section   = spec.section or "widgets"
    local sharedKey = spec.key or spec.name
    -- Opt-in per frame, not a blanket change: a module that wants one placement across the account
    -- keeps it by saying nothing.
    local key       = NE.FramePositionKey(sharedKey, spec.perCharacter)
    seedPerCharacterPosition(section, sharedKey, key)
    local content   = spec.frame

    -- DragonUI's CreateUIFrame labels the editor handle with `addon.L[frameName]`. AceLocale's
    -- read metatable fires a non-breaking error for any key its locale doesn't define, so every
    -- frame we register printed "Missing entry for 'CooldownViewerBuffBar'" on login.
    --
    -- The table GetLocale returns has an `__index` hook but NO `__newindex`, so seeding our own key
    -- is a plain assignment into a runtime table — it does not modify DragonUI (CONTRACTS §0), and
    -- it upgrades the handle's label from the raw frame name to something readable.
    if spec.label and type(dragon.L) == "table" then
        pcall(function()
            if rawget(dragon.L, spec.name) == nil then dragon.L[spec.name] = spec.label end
        end)
    end

    -- The draggable handle. Sized to the content's current footprint; kept in sync below.
    local w = math.max(content:GetWidth() or 0, 32)
    local h = math.max(content:GetHeight() or 0, 32)
    local okAnchor, anchor = pcall(dragon.CreateUIFrame, w, h, spec.name)
    if not okAnchor or not anchor then
        warn("CreateUIFrame failed for '" .. tostring(spec.name) .. "': " .. tostring(anchor))
        return
    end

    -- Position the ANCHOR (saved position wins over the module's default), then pin content to it.
    if not NE.ApplySavedFramePosition(anchor, section, key) then
        local d = spec.defaultPoint
        anchor:ClearAllPoints()
        if d then
            anchor:SetPoint(d.point or "CENTER", UIParent, d.relativePoint or d.point or "CENTER",
                            d.x or 0, d.y or 0)
        else
            anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    content:ClearAllPoints()
    content:SetPoint("CENTER", anchor, "CENTER", 0, 0)

    -- Keep the grab target matching what's actually on screen as icons come and go.
    content:SetScript("OnSizeChanged", function(f)
        local cw, ch = f:GetWidth(), f:GetHeight()
        if cw and ch and cw > 0 and ch > 0 then anchor:SetSize(cw, ch) end
    end)

    -- Optional: this frame's own settings, on the frame, in edit mode.
    if type(spec.editorSettings) == "function" then attachEditorSettings(anchor, spec) end

    local ok, err = pcall(dragon.RegisterEditableFrame, dragon, {
        name       = spec.name,
        frame      = anchor,
        configPath = { section, key },
        -- Always offer it in edit mode. A HUD frame that is empty right now still needs to be
        -- positionable — that is what showTest is for.
        editorVisible = spec.editorVisible or function() return true end,
        showTest   = spec.showTest,
        hideTest   = spec.hideTest,
        onHide     = function()
            if spec.hideTest then spec.hideTest() end
            if spec.onHide then spec.onHide() end
        end,
    })
    if not ok then
        warn("RegisterEditableFrame failed for '" .. tostring(spec.name) .. "': " .. tostring(err))
        return
    end

    spec.frame.editorAnchor = anchor
    return anchor
end

function NE.RegisterPanel(spec)
    if type(spec) ~= "table" or not spec.id then
        warn("RegisterPanel called without a spec.id; ignored.")
        return
    end

    local id    = spec.id
    local title = spec.title or id
    local desc  = spec.desc or ""

    -- (1) DB default. Guarded: profile may not exist yet pre-login; the default
    -- is re-asserted in OnReady for panels that registered early.
    local modules = NE.modules and NE.modules._dragonModulesTable and NE.modules._dragonModulesTable(true)
    local moduleKey = NE.modules and NE.modules.CanonicalName and NE.modules.CanonicalName(id) or ("ne_" .. id)
    if modules then
        if type(modules[moduleKey]) ~= "table" then
            modules[moduleKey] = { enabled = true }
        elseif modules[moduleKey].enabled == nil then
            modules[moduleKey].enabled = true
        end
    end

    -- enabled() reads the live DB value, defaulting to true when DB is absent.
    local function isEnabled()
        if NE.modules and type(NE.modules.IsEnabled) == "function" then
            return NE.modules.IsEnabled(id)
        end
        return true
    end

    -- (2) Boot dispatcher (Core agent's Core/Modules.lua). No-op gracefully if
    -- NE.modules is nil so load order can't crash.
    if NE.modules and type(NE.modules.Register) == "function" then
        local ok, err = pcall(function()
            NE.modules.Register{
                name    = id,
                default = true,
                onBoot  = function()
                    -- Only open/show when the panel is enabled in config.
                    if isEnabled() and spec.bootFn then
                        spec.bootFn()
                    elseif isEnabled() and spec.autoOpen ~= false and spec.openFn then
                        spec.openFn()
                    end
                end,
            }
        end)
        if not ok then
            warn("NE.modules.Register failed for '" .. id .. "': " .. tostring(err))
        end
    end

    -- (3) DragonUI ModuleRegistry. Real base API is either
    -- NE.dragon.ModuleRegistry:Register(name, moduleTable, displayName, desc, order)
    -- or the convenience wrapper NE.dragon:RegisterModule(...). Prefer whichever
    -- the base actually exposes. We pass a lightweight module table carrying an
    -- Enable refresh hook so DragonUI's enable/disable plumbing can drive us.
    local moduleTable = {
        ne_id = id,
        Enable = function()
            if spec.openFn then spec.openFn() end
        end,
        Disable = function()
            if spec.closeFn then spec.closeFn() end
        end,
        Refresh = function()
            if isEnabled() then
                if spec.refreshFn then spec.refreshFn()
                elseif spec.openFn then spec.openFn() end
            else
                if spec.closeFn then spec.closeFn() end
            end
        end,
    }
    local dragon = NE.dragon
    if dragon then
        local registered = false
        local mr = dragon.ModuleRegistry
        if mr and type(mr.Register) == "function" then
            local ok, err = pcall(mr.Register, mr, "ne_" .. id, moduleTable, title, desc, spec.order)
            if ok then
                registered = true
            else
                warn("ModuleRegistry:Register failed for '" .. id .. "': " .. tostring(err))
            end
        end
        if not registered and type(dragon.RegisterModule) == "function" then
            local ok, err = pcall(dragon.RegisterModule, dragon, "ne_" .. id, moduleTable, title, desc, spec.order)
            if not ok then
                warn("RegisterModule failed for '" .. id .. "': " .. tostring(err))
            end
        elseif not registered and not mr then
            warn("DragonUI exposes neither ModuleRegistry nor RegisterModule; '" .. id .. "' not in module list.")
        end
    end

    -- (4) Mover — OPTIONAL, and absent on current DragonUI.
    --
    -- DragonUI deleted this system: core/core.xml now reads "module_base.lua / movers.lua removed —
    -- EditableFrames + PositionPresets own layout". core/movers.lua is still on disk but no longer
    -- in the load manifest, so addon.MoversSystem is simply nil. That used to print a red error per
    -- registered window on every /reload (six of them: Professions, AuctionHouse, Guild, Social,
    -- LFG, EncounterJournal), which is noise, not a fault.
    --
    -- NOTHING IS LOST. Every NewEra window drags itself — its own StartMoving/StopMovingOrSizing
    -- handlers, and NE.FrameUtil.PersistWindowPosition (db.windowPos[key]) for the ones that persist
    -- across sessions. And the mover was already inert here anyway: its drag overlay only appears in
    -- MoversSystem config mode, reachable solely from a dead `elseif` in DragonUI's core/commands.lua
    -- (addon.EditorMode always exists, so the first branch always won), so it never saved a position.
    --
    -- Deliberately NOT migrated to dragon:RegisterEditableFrame. That is the HUD seam — see
    -- NE.RegisterHUDFrame below — and putting toggled WINDOWS in it would have `/dui edit` show and
    -- reposition them through a second system that fights their own persisted position.
    --
    -- Kept live for older DragonUI installs that still ship movers.lua.
    if dragon and dragon.MoversSystem and type(dragon.MoversSystem.RegisterMover) == "function" then
        if spec.frame then
            local ok, err = pcall(function()
                dragon.MoversSystem:RegisterMover{
                    name         = "ne_" .. id,
                    parent       = spec.frame,
                    text         = title,
                    configPath   = { "widgets", "ne_" .. id },
                    defaultPoint = spec.defaultPoint,
                }
            end)
            if not ok then
                warn("RegisterMover failed for '" .. id .. "': " .. tostring(err))
            end
        end
        -- No frame yet (lazily-created panel): the panel re-calls RegisterPanel
        -- or registers its mover itself once the frame exists. Silent by design.
    end
    -- No `else` warn: MoversSystem being absent is the expected state on current DragonUI (see above).

    -- (5) QA harness list.
    if NE.qa then
        NE.qa.modules = NE.qa.modules or {}
        table.insert(NE.qa.modules, {
            name  = title,
            frame = spec.frame,
            open  = spec.openFn,
            close = spec.closeFn,
        })
    end

    -- (6) Options tab list (rendered by Options.lua). Store a refresh fn so the
    -- toggle callback can re-run this panel's enable without knowing internals.
    table.insert(NE.optionPanels, {
        id      = id,
        title   = title,
        desc    = desc,
        order   = spec.order or 999,
        refresh = moduleTable.Refresh,
    })

    return moduleTable
end
