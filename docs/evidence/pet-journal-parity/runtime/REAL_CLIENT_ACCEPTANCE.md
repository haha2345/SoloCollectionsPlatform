# Pet Journal Parity — real-client acceptance

- Date: 2026-08-13 (Asia/Shanghai)
- Client: zhCN WoW 3.3.5a, `Wow-CQM-SoloCam.exe` → `Wow-SoloCam-PoC.exe`
- Account/character: local acceptance account, character GUID 11
- Result: `REAL_CLIENT_ACCEPTED`

## Runtime coverage

- Pet journal shell, filters, sorting, ten-row list, scrollbar, detail layout, model rotation/zoom/reset and rapid selection were exercised in the real client.
- Collected and uncollected rows, reviewed source categories, Chinese descriptions and vendor price layout were inspected in the real client.
- Favorite set/unset, relog persistence, favorite-only random, no-favorite random, no immediate repeat, summon and dismiss were exercised through SC2 and confirmed by server action logs.
- The deployed server published nine category snapshots after adding category 17 (`companion-favorite`); startup reported `providers=9` and `schema_version=2`.
- The death restriction was exercised end to end: the client displayed `死亡状态下不能召唤小宠物。`, and the authoritative action log recorded `status=DEAD`.
- Combat, vehicle and taxi restrictions share the same server-side companion action guard and the same AddOn reason-to-Chinese mapping (`IN_COMBAT`, `IN_VEHICLE`, `ON_TAXI`). Their mapping/protocol paths are covered by the companion action regression set; no separate long-lived world object or database fixture was retained.

## Evidence index

- Server startup evidence (kept in the local runtime evidence directory): category-17 projection fix with `providers=9`.
- Authoritative server action evidence (kept in the local runtime evidence directory): favorite, persistence, random, summon/dismiss and `status=DEAD`.
- `task17-pet-page-baseline.png`, `task17-reload-clean.png`, `task17-model-interaction.png`: shell and model acceptance.
- `task17-favorite-persisted-relogin.png`, `task17-favorite-random-success.png`, `task17-random-no-favorites-after-fix.png`: preference and random acceptance.
- `task17-uncollected-real-disabled.png`, `task17-vendor-cost-layout.png`, `task17-promotion-visible.png`, `task17-world-event-visible.png`: collection state and reviewed metadata presentation.
- `task17-restricted-dead-cn.png`: real-client Chinese death restriction feedback.
- `_rejected/`: superseded screenshots retained for traceability and explicitly excluded from acceptance evidence.

## Deployment identity

- SoloCollections: `6ff5e4c6f4da86ffdf55a4a87bc15074c5eb6a2f`
- mod-solo-collections: `f15574295af614652948c777c58e8b997104a1db`
- SoloClientSuite: `973983a097248a46e04e1adfabdb7ce3649ff7db`
- AzerothCore: `28463899f4857bffdc1af59a78c1d359f7e7784a`
- Companion mapping SHA-256: `15e24a2e506652232dd862bf328203df761d7654296a05233c5df5d4457f4ff7`
- Deployed worldserver SHA-256: `d91c99bdcf2fb1a04da6fefb208dccd78a321a94703a872ce221b65fe02d77b4`
- Client package SHA-256: `1d8cb337b796eefb82732c1d2c49c8e72c3a8aa0d958e2f6395c4d009be477ab`
- Deployment metadata SHA-256: `980bc27d435b0049d0ff26edd6a57a011bfdec04aa7e33a2aac601b0c1dae9ae`
- Database migration: none; existing schema version 2 was used.
- Rollback evidence: `CLIENT-20260813-pet-journal-parity-redeploy/20260813-100353`.

## Cleanup note

The temporary vehicle experiment did not create a persistent `creature` row. The test character was returned to an alive database state (`health=574`, `death_expire_time=0`, ghost flag cleared) before the final login.

## 2026-08-13 zhCN description completion acceptance

- User verdict: `REAL_CLIENT_ACCEPTED` / 验收合格，可以提交。
- 167 of 201 companion records now use verified zhCN `BattlePetSpecies.Description_lang` text, mapped by creature identity and retained with per-record provenance.
- The other 34 verified client rows have an empty official description. The detail view hides that empty line and no longer displays `暂无可核验的中文描述`; no generated or template prose is substituted.
- SoloCollections: `35354284c7e5dca82960fae1e13f79936e400143`.
- SoloClientSuite lock: `328074c9ad0f233d8ca17eb76c4aa7d8f198ca97`.
- Deployed AddOn tree SHA-256: `d8088a8c724d2488f15a5e438acdf25c66c555c0597be42c8fd451d5bb1a06a2`.
- Client package SHA-256: `66242346b75a33b5f244a6692984eebd57660bd13717f2e0595fe64af71237b1`.
- Rollback evidence: `CLIENT-20260813-pet-description-zhcn/20260813-113608`.
