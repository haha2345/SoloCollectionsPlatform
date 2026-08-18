-- DragonUI_NewEra/compat/Events.lua — event-surface gap-fills.
--
-- (1) Frame:RegisterUnitEvent — added in 5.0 (MoP). NewEra uses it throughout the CooldownViewer
--     to engine-filter UNIT_AURA / UNIT_SPELLCAST_* down to "player" (and "target"), which matters
--     for more than tidiness: an unfiltered UNIT_AURA delivers every raid/party/nameplate unit's
--     aura churn to the handler, per plate per tick in big pulls.
--
--     !!!ClassicAPI DOES implement the semantics (Util/EventHandler.lua:189) but only inside its
--     `Private` namespace — `Private.EventHandler` is never exported to _G, so we cannot delegate.
--     We therefore implement it ourselves on the Frame metatable: RegisterEvent + a per-frame,
--     per-event allowed-unit set, enforced by wrapping that frame's OnEvent handler.
--
--     Only the frames that actually call RegisterUnitEvent pay the wrapper cost — the metatable
--     gains the method, but the SetScript interception is installed per-instance, on demand.
--
-- (2) NE.EV_LEARNED_SPELL — NewEra's flavour-correct learn-a-spell event name.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

-- ---------------------------------------------------------------------------
-- (1) Frame:RegisterUnitEvent
-- ---------------------------------------------------------------------------

-- The shared Frame method table. Adding here gives every frame the method without a per-frame cost.
local frameProto
do
  local probe = CreateFrame("Frame")
  local mt = getmetatable(probe)
  frameProto = mt and mt.__index
end

if frameProto and not frameProto.RegisterUnitEvent then

  -- Wrap an OnEvent handler so a filtered event whose unit isn't in the allow-set is dropped before
  -- the handler sees it. The filter table is read at DISPATCH time (not capture time) so registering
  -- more filtered events later works without re-wrapping.
  local function filtering(inner)
    return function(self, event, ...)
      local allowed = self._neUnitFilter and self._neUnitFilter[event]
      if allowed then
        local unit = ...
        if not (unit and allowed[unit]) then return end
      end
      return inner(self, event, ...)
    end
  end

  -- Install the interception on one frame. Idempotent. Handles both orders: a handler already set
  -- via SetScript (re-wrapped now) and one set later (wrapped by the shadowing SetScript).
  local function ensureFilter(self)
    if self._neUnitFilterHooked then return end
    self._neUnitFilterHooked = true
    self._neUnitFilter = {}

    local rawSetScript = frameProto.SetScript
    local existing = self:GetScript("OnEvent")
    if existing then rawSetScript(self, "OnEvent", filtering(existing)) end

    -- Instance field shadows the metatable method for this frame only.
    self.SetScript = function(s, script, handler)
      if script == "OnEvent" and handler then handler = filtering(handler) end
      return rawSetScript(s, script, handler)
    end
  end

  -- RegisterUnitEvent(event [, unit1, unit2, ...]). With no units this degrades to RegisterEvent,
  -- matching the real API.
  function frameProto.RegisterUnitEvent(self, event, ...)
    if not event then return end
    ensureFilter(self)
    local n = select("#", ...)
    if n > 0 then
      local set = {}
      for i = 1, n do
        local u = select(i, ...)
        if u then set[u] = true end
      end
      self._neUnitFilter[event] = set
    else
      self._neUnitFilter[event] = nil
    end
    return self:RegisterEvent(event)
  end

  -- Unregistering must drop the filter too, or a later plain RegisterEvent on the same event would
  -- silently inherit the old unit restriction.
  local rawUnregister = frameProto.UnregisterEvent
  function frameProto.UnregisterEvent(self, event)
    if self._neUnitFilter then self._neUnitFilter[event] = nil end
    return rawUnregister(self, event)
  end

  if NE.compat then NE.compat.unitEvents = true end
end

-- ---------------------------------------------------------------------------
-- (2) Learn-a-spell event
-- ---------------------------------------------------------------------------
-- NewEra picks this per flavour (Era/TBC fire LEARNED_SPELL_IN_TAB). 3.3.5a fires
-- LEARNED_SPELL_IN_TAB as well; the modern SPELLS_CHANGED-adjacent names don't exist here.
NE.EV_LEARNED_SPELL = "LEARNED_SPELL_IN_TAB"
