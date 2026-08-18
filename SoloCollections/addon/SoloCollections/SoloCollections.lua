SoloCollections = SoloCollections or {}

local SC = SoloCollections

SC.NAME = "SoloCollections"
SC.VERSION = "0.2.0"
SC.BUILD_CHANNEL = SC.BUILD_CHANNEL
    or (GetAddOnMetadata and GetAddOnMetadata(SC.NAME, "X-SoloCollections-BuildChannel"))
    or "stable"
SC.DEFAULT_UI_SHELL = "DRAGONUI"
SC.PROTOCOL = "SC1"
SC.PROTOCOL_VERSION = 1
SC.TABS = {
    "MOUNTS",
    "PETS",
    "WARDROBE",
}
SC.WARDROBE_TABS = {
    "ITEMS",
    "SETS",
}
SC.Data = SC.Data or {}
SC.Pages = SC.Pages or {}
SC.UI = SC.UI or {}
