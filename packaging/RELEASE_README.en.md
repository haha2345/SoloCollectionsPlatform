# SoloCollections v{{VERSION}} package

Close the client/server and back up every same-name target before installation.

**External media: [Baidu Netdisk](https://pan.baidu.com/s/1XyCl8PaimIVPPSTNUDaIOg?pwd=j8sk)**  
**Access code: `j8sk`**

The AddOn archive in the GitHub release excludes extracted `Media/Retail`
assets by default. Project-authored placeholders remain, but some buttons or
previews can be blank until the external media pack is installed.

1. Extract `addon/SoloCollections-v{{VERSION}}.zip` under `Interface/AddOns`.
2. Copy `server/solo_collections.lua` to the ALE `lua_scripts` directory and
   restart the world server.
3. Copy `client-patches/Data/Patch-W.MPQ` to client `Data`.
4. Use the bundled `{{LOCALE_PATCH}}` only with `{{LOCALE}}`. Build
   `patch-enUS-6.MPQ`, `patch-zhTW-6.MPQ`, etc. from the matching clean client.
5. Put `SoloCam.dll` and `poc_patch.py` in the client root. Run the patcher only
   if the original `Wow.exe` SHA-256 is
   `AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8`:

```powershell
python .\poc_patch.py .\Wow.exe .\Wow-SoloCam-PoC.exe
```

6. Verify and extract the external media pack over the client root.
7. Validate the journal and previews in game.

Do not overwrite an existing MPQ without identifying and backing it up. The ALE
script is currently a demo/action bridge, not a complete persistent account
collection service. This project does not grant redistribution rights for game
executables or third-party media. Project-authored code uses
`GPL-3.0-or-later`; see `LICENSE`. Verify files against `SHA256SUMS.txt`.
