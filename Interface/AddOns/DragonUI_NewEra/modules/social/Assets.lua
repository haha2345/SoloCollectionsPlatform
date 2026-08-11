-- DragonUI_NewEra/modules/social/Assets.lua — Social window art registration.
--
-- Owner-supplied BLP (2026-07-17): the Social window's portrait icon, matching NewEra's own
-- Interface\FriendsFrame\Battlenet-Portrait — a retail-only asset that doesn't exist on this
-- 3.3.5a client (see modules/social/Window.lua's buildChrome history), so the real art had to be
-- shipped locally instead of referenced by native path. Physical file lives under Textures\Guild\
-- (wherever the owner's asset pipeline dropped it); this registration just points our fdid at it.
--
-- Load order: BEFORE Window.lua (any NE.tex reference to this fdid).

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

NE.tex.RegisterLocal(626421, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Guild\\626421-battlenet-portrait.blp")
