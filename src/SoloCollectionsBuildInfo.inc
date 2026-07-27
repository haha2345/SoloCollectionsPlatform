#ifndef SOLO_COLLECTIONS_BUILD_INFO_WRAPPER_INC
#define SOLO_COLLECTIONS_BUILD_INFO_WRAPPER_INC

#if defined(__has_include)
#  if __has_include("generated/SoloCollectionsBuildInfo.inc")
#    include "generated/SoloCollectionsBuildInfo.inc"
#    define SOLO_COLLECTIONS_HAS_PINNED_BUILD_INFO 1
#  endif
#endif

#if !defined(SOLO_COLLECTIONS_HAS_PINNED_BUILD_INFO)
namespace SoloCollectionsBuildInfo
{
inline constexpr char addonCommit[] = "UNPINNED";
inline constexpr char moduleCommit[] = "UNPINNED";
inline constexpr char coreCommit[] = "UNPINNED";
inline constexpr char metadataVersion[] = "UNPINNED";
inline constexpr char assetPackVersion[] = "UNPINNED";
inline constexpr char mappingHash[] = "UNPINNED";
inline constexpr char presentationHash[] = "UNPINNED";
inline constexpr char mountMappingHash[] = "UNPINNED";
inline constexpr char companionMappingHash[] = "UNPINNED";
inline constexpr char toyMappingHash[] = "UNPINNED";
inline constexpr char appearanceMappingHash[] = "UNPINNED";
inline constexpr char setMappingHash[] = "UNPINNED";
}
#endif

#endif
