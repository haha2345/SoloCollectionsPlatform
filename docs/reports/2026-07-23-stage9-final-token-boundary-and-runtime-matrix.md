# Stage 9 final candidate: token boundary and runtime matrix

Date: 2026-07-23  
Status: agent-executable Stage 9 work complete; final user acceptance is still required.  
Scope: local candidate only. No remote push, public release, database change, or client asset distribution was performed.

## Candidate and provenance

The final clean, static-module candidate is:

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-clean-r2-20260723\candidate\round2-20260723T122520Z-0bd5bba-397a7e5-4cc67a3
```

| Field | Value |
| --- | --- |
| bundleId | `round2-20260723T122520Z-0bd5bba-397a7e5-4cc67a3` |
| AddOn | `0bd5bbaecbd16ad59e0399d9c5db2cf92a7e06c4` |
| module | `397a7e50265131154282be434141dd585d0ceb14` |
| Core | `4cc67a316d2bec9faf27c3392634282e70cacbe0` |
| metadataVersion | `2026.07.23.2` |
| assetPackVersion | `round-two-stage8-weapon-presentation-v2` |
| static `worldserver.exe` | x64, SHA-256 `f0d6359ade1bfa46acf584823c6b5a17e129f5360c7bb0842e22333488837f22` |
| bundle verifier | passed; 72 manifest members and installed verifier passed |

The candidate was built from clean F-drive worktrees using the fixed evidence pack. The AddOn suite passed `320` tests with `3` specified skips; the module suite passed `133` tests and the native CTest suite passed `2/2`.

## Token-boundary correction

The versioned asset token `round-two-stage8-weapon-presentation-v2` is 39 bytes. The previous 32-byte SC2 token limit caused a valid candidate HELLO to be rejected before the client could obtain an authoritative acknowledgement.

The module commit raises the shared server bound to 64 bytes. The final AddOn commit makes the client parser, schema/golden fixture, Python contract, and test boundary agree on the same 64-byte limit. This is a protocol-contract correction; it does not loosen action authorization or make a mismatched asset pack renderable.

## Final real-client evidence

All new persistent evidence below is on F:. The live test deployment was made through the release installer using a pre-deploy snapshot and the candidate backup manifest.

| Scenario | Result | Durable evidence |
| --- | --- | --- |
| Normal login, `/reload`, worldserver restart then relogin | Three independent runs were authoritative, SC2-connected, `CollectionState=Ready`, `assetMismatch=false`; handshake completion was 0.652 s, 0.604 s, and 0.657 s. | `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-runtime-20260723\final-token64-v2-20260723-2026\status-matrix\SoloCollectionsStage9StatusAudit.normal-reload-serverrestart.lua` |
| Asset-pack mismatch, final 64-byte protocol | Client sent a 61-byte mismatched token, remained authoritative after ACK, set `assetMismatch=true`, hid the standalone/character hosts, and displayed `资源包版本不匹配`. The card result was `UNAVAILABLE`; no unsafe icon-to-model pass-through occurred. | `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-runtime-20260723\final-token64-v2-20260723-2026\asset-mismatch-token64-v3-20260723\SoloCollectionsAssetMismatchAudit.pass.lua` |
| Normal candidate after mismatch test | The mismatched AddOn clone and its audit TOC were disabled, then the final candidate AddOn was restored. A real client login and `/sc` view showed the one-hand-axe grid as independent weapon models, not fallback icons. | Current CUA real-client view; production AddOn `Catalog.lua`, `CollectionState.lua`, and `Wardrobe.lua` SHA-256 matched the final candidate before launch. |
| DLL absent / stock fallback | Standalone target remained `UNAVAILABLE`, object/character hosts were hidden, and `CLIENT_MODEL_READY_TIMEOUT` was rendered as an explicit unavailable state. | `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-runtime-20260723\negative-capability-v2\dll-absent-stock-explicit-unavailable-20260723-1857\SoloCollectionsStage9StockAudit.result.lua` |
| Cold/hot cache and weapon presentation | Existing Stage 8 evidence used the unchanged asset pack, generated catalog, model renderer, and cache path: 3,690 terminal rows (`3,541 READY`, `149 UNAVAILABLE`, `0 failed`) plus 134 family samples (`131 READY`, `3 UNAVAILABLE`, `0 failed`). | `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-runtime-20260723\weapon-presentation-matrix-v2` |
| Ten-minute stability soak | 600.001 s, 150 cycles, 598 samples, fixed 18-card pool, 0 failures, authoritative SC2 session, no black model/NPC/character fallback, and `memoryStable=true`. Start/warmup/max/end were 168682.948/177345.531/203985.206/193880.190 KB. | `F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-runtime-20260723\final-token64-v2-20260723-2026\stability-pass\SoloCollectionsStage9SoakAudit.pass.lua` |

The first soak-audit failures were test-harness false positives: WoW normalized model-path case while the audit compared it case-sensitively. The F-only audit was corrected to compare case-insensitively; production code was not changed. The prior diagnostic/failure captures remain preserved alongside the final pass for traceability.

## Mismatch semantics and rollback

The negative mismatch test intentionally replaces only the AddOn generated top-level `assetPackVersion` with `round-two-stage8-weapon-presentation-v2-stage9-mismatch-probe` (61 bytes). It is not a production candidate and was used solely to prove fail-closed behavior. The server now acknowledges the valid-width HELLO; the client explicitly gates standalone rendering through `assetMismatch` instead of relying on a timeout/rejected handshake.

The candidate installer produced a backup manifest at:

```text
F:\1_projects\wow_projects\SoloCollectionsPlatform\_work\stage9-clean-r2-20260723\candidate\round2-20260723T122520Z-0bd5bba-397a7e5-4cc67a3\backup\backup-manifest.json
```

Rollback is performed only with the paired release tool and that manifest:

```powershell
& .\tools\release\Restore-RoundTwoBundle.ps1 `
  -BackupManifest '<candidate>\backup\backup-manifest.json' `
  -Profile '<F-drive deployment-profile.json>' `
  -StopServer
```

The restore tool verifies the currently installed candidate hashes before restoring exact backed-up targets; it does not delete broad client directories or WDB caches. Temporary validation AddOns are not part of the candidate bundle and are kept disabled while the final candidate is displayed for user review.

## Remaining gate

All agent-executable Stage 9 checks are closed. The plan intentionally retains one unchecked item: the user must complete final hands-on acceptance before the plan status changes from “实施中” to “已完成”.
