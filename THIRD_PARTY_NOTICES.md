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

Game names and marks belong to their respective owners. This project must not
distribute proprietary game executables or archives.
