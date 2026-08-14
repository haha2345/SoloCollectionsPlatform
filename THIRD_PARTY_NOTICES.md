# Third-party notices and provenance audit

This file is a publication checklist, not a completed grant of rights.

| Area | Current evidence | Required before public release |
| --- | --- | --- |
| AddOn media | `addon/SoloCollections/Media/assets.json` records a mix of project-authored and Retail client-derived media | Replace non-redistributable files with same-path placeholders and record licenses |
| UI references | Architecture/history notes reference Blizzard UI layouts | Confirm no copied code requiring additional notice; document inspiration separately |
| SoloCam patcher | `poc_patch.py` describes a narrower implementation than a reference WotLK extension patcher | Perform line-by-line provenance review and add any required license/notice |
| Python packages | `capstone` and `pefile` are development dependencies | Preserve their upstream license notices in any bundle that redistributes them |
| StormLib | MPQ tooling dynamically loads the separately supplied x64 StormLib library; upstream uses the MIT license | Link to upstream, preserve its license when redistributing the DLL, and do not commit local binaries |
| AzerothCore/ALE API | Server bridge targets the AzerothCore ALE environment | Document compatibility; do not imply AzerothCore endorsement |
| DragonUI integrated UI | Not vendored by the public SoloCollections source release | The optional integrated archive is assembled from SoloClientSuite; pinned commits, patch state, hashes, and license review state are recorded in its `upstream/suite-lock.json` |
| ezCollections wardrobe cards | `addon/SoloCollections/UI/EzCollections/Templates.lua` adapts the 78x104 wardrobe card chrome from the audited ezCollections 2.2 source tree | Preserve this provenance record, audit the upstream grant/license before public redistribution, and keep proprietary game art in the separately assembled client asset package |
| Transmorpher item preview | The namespaced armor/weapon preview setup and lifecycle projection is pinned to upstream commit `8a8140fa54e424699da00d3a21359b43b79efddc`. SHA-256: `PreviewList.lua` `FE0DB99A4D85342A7FC2566F4EC4AE12BFCB3C1717839C8088BBB21F98B66EFE`; `DressingRoom.lua` `E98DCC274323E3283DD402EEB25E1BCC8E2C76C69797450584CAB2EB3E7806AA`; `QueryItem.lua` `4F170E6A103899B0E4D86E78D361F8940EEFEFCE8679D34D1F7D4D479A10E22F`; `PreviewSetupAPI.lua` `73D11A95D9ECCFDF9B3BC6765B9938CF6D7F2A482AA68C4142AAF3601AC096FD`; `PreviewSetupDB.lua` `B550F596C7FE94D5B3844D9ECD2D5A0B44BAD2E6E2B2525C3A6A92FCD3D039B4`. The project owner explicitly authorized this project use on 2026-08-14. | The audited upstream snapshot has no explicit license file; retain the permission record and complete a redistribution-rights review before any public source or binary release |

Game names and marks belong to their respective owners. This project must not
distribute proprietary game executables or archives.
