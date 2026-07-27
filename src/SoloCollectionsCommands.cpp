#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsBackend.h"
#include "SoloCollectionsCreaturePreviewService.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsProtocolScript.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"

#include "Chat.h"
#include "CommandScript.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "Player.h"
#include "QueryResult.h"
#include "RBAC.h"
#include "ScriptMgr.h"
#include "StringConvert.h"
#include "Tokenize.h"
#include "WorldSession.h"

#include <optional>
#include <chrono>
#include <algorithm>
#include <string>
#include <string_view>
#include <vector>

using namespace Acore::ChatCommands;

namespace SoloCollections
{
namespace
{
#include "SoloCollectionsBuildInfo.inc"

constexpr std::uint32_t RBAC_SC_STATUS = 71050;
constexpr std::uint32_t RBAC_SC_ACCOUNT = 71051;
constexpr std::uint32_t RBAC_SC_WRITE = 71052;
constexpr std::uint32_t RBAC_SC_RELOAD = 71053;
constexpr std::uint32_t RBAC_SC_RECONCILE = 71054;

std::string_view SchemaStateName(AccountStoreSchemaState state)
{
    switch (state)
    {
        case AccountStoreSchemaState::Checking: return "checking";
        case AccountStoreSchemaState::Ready: return "ready";
        case AccountStoreSchemaState::Failed: return "failed";
    }
    return "unknown";
}

std::string_view CacheStateName(AccountCacheLoadState state)
{
    switch (state)
    {
        case AccountCacheLoadState::Loading: return "loading";
        case AccountCacheLoadState::Ready: return "ready";
        case AccountCacheLoadState::Failed: return "failed";
    }
    return "unknown";
}

std::optional<AccountId> ResolveAccount(ChatHandler* handler, Optional<uint32> requested)
{
    if (requested && *requested != 0)
        return AccountId(*requested);
    if (handler->GetSession())
        return AccountId(handler->GetSession()->GetAccountId());
    handler->SendErrorMessage("An account ID is required from the console.");
    return std::nullopt;
}

std::uint32_t ActorAccountId(ChatHandler* handler)
{
    return handler->GetSession() ? handler->GetSession()->GetAccountId() : 0;
}

std::uint32_t ActorGuid(ChatHandler* handler)
{
    return handler->GetPlayer() ? handler->GetPlayer()->GetGUID().GetCounter() : 0;
}

AccountCollectionMutation BuildGmMutation(
    ChatHandler* handler, AccountId accountId, CollectionTypeId typeId, CollectionId collectionId,
    CollectionMutationKind kind, LoginGeneration generation = {})
{
    return {
        accountId,
        generation,
        { typeId, collectionId },
        kind,
        CollectionSourceKind::GameMaster,
        0,
        0,
        ActorAccountId(handler),
        ActorGuid(handler),
    };
}

bool RejectAndAudit(ChatHandler* handler, AccountCollectionMutation const& mutation, CollectionReasonCode reason)
{
    (void)GetAccountCollectionStore().RecordRejectedMutation(mutation, reason);
    handler->SendErrorMessage("SoloCollections request rejected: reason={} localization={}",
        ToStableReasonCode(reason), ReasonCodeLocalizationKey(reason));
    return true;
}

class SoloCollectionsCommandScript final : public CommandScript
{
public:
    SoloCollectionsCommandScript() : CommandScript("SoloCollectionsCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable soloCollectionsTable =
        {
            { "status",    HandleStatus,    RBAC_SC_STATUS,    Console::Yes },
            { "benchmark", HandleBenchmark, RBAC_SC_STATUS,    Console::Yes },
            { "account",   HandleAccount,   RBAC_SC_ACCOUNT,   Console::Yes },
            { "grant",     HandleGrant,     RBAC_SC_WRITE,     Console::Yes },
            { "revoke",    HandleRevoke,    RBAC_SC_WRITE,     Console::Yes },
            { "reload",    HandleReload,    RBAC_SC_RELOAD,    Console::Yes },
            { "resync",    HandleResync,    RBAC_SC_RELOAD,    Console::Yes },
            { "import",    HandleImport,    RBAC_SC_RECONCILE, Console::Yes },
            { "reconcile", HandleReconcile, RBAC_SC_RECONCILE, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "solocollections", soloCollectionsTable },
        };
        return commandTable;
    }

    static bool HandleStatus(ChatHandler* handler)
    {
        handler->PSendSysMessage("build.addon_commit={}", SoloCollectionsBuildInfo::addonCommit);
        handler->PSendSysMessage("build.module_commit={}", SoloCollectionsBuildInfo::moduleCommit);
        handler->PSendSysMessage("build.core_commit={}", SoloCollectionsBuildInfo::coreCommit);
        handler->PSendSysMessage("build.metadata_version={}", SoloCollectionsBuildInfo::metadataVersion);
        handler->PSendSysMessage("build.asset_pack_version={}", SoloCollectionsBuildInfo::assetPackVersion);
        handler->PSendSysMessage("build.mapping_hash={}", SoloCollectionsBuildInfo::mappingHash);
        handler->PSendSysMessage("build.presentation_hash={}", SoloCollectionsBuildInfo::presentationHash);
        handler->PSendSysMessage("build.type.mount={}", SoloCollectionsBuildInfo::mountMappingHash);
        handler->PSendSysMessage("build.type.companion={}", SoloCollectionsBuildInfo::companionMappingHash);
        handler->PSendSysMessage("build.type.toy={}", SoloCollectionsBuildInfo::toyMappingHash);
        handler->PSendSysMessage("build.type.appearance={}", SoloCollectionsBuildInfo::appearanceMappingHash);
        handler->PSendSysMessage("build.type.set={}", SoloCollectionsBuildInfo::setMappingHash);
        AccountStoreDiagnostics store = GetAccountCollectionStore().Diagnostics();
        AccountCacheDiagnostics cache = GetAccountCollectionCache().Diagnostics();
        CollectionProviderRegistry& providers = GetCollectionProviderRegistry();
        std::size_t enabled = 0;
        std::size_t readOnly = 0;
        std::size_t disabled = 0;
        for (CollectionTypeId typeId : providers.TopologicalOrder())
        {
            CollectionProviderRuntimeState const* state = providers.State(typeId);
            if (!state || state->Mode == CollectionProviderMode::Disabled)
                ++disabled;
            else if (state->Mode == CollectionProviderMode::ReadOnly)
                ++readOnly;
            else
                ++enabled;
        }
        std::size_t pendingWrites = store.PendingMutations + store.PendingAudits +
            store.PendingMigrationMarkers;

        handler->PSendSysMessage(
            "SoloCollections backend={} writes={} shadow={} preview={} schema={} providers_ready={} providers_readonly={} "
            "providers_disabled={} online_accounts={} cache_entries={} sessions={} states={}/{}/{} pending_writes={} "
            "pending_loads={} pending_mutations={} pending_audits={} pending_deltas={} evictions={}",
            BackendModeName(GetBackendMode()), store.WritesEnabled ? 1 : 0,
            IsShadowComparisonEnabled() ? 1 : 0, IsCreaturePreviewEnabled() ? 1 : 0, SchemaStateName(store.SchemaState),
            enabled, readOnly, disabled, cache.SessionCount, cache.EntryCount,
            cache.SessionCount, cache.LoadingCount, cache.ReadyCount, cache.FailedCount,
            pendingWrites,
            store.PendingLoads, store.PendingMutations, store.PendingAudits,
            cache.PendingDeltaCount, cache.EvictionScheduledCount);
        handler->PSendSysMessage(
            "SoloCollections totals loads_ok={} loads_failed={} mutations_ok={} mutations_failed={}",
            store.SuccessfulLoads, store.FailedLoads, store.SuccessfulMutations, store.FailedMutations);
        Sc2ServerDiagnostics protocol = Sc2ProtocolDiagnostics();
        handler->PSendSysMessage(
            "SoloCollections cache opens={} hits={} misses={} total_evictions={} owned={} ready_deltas={} estimated_bytes={}",
            cache.OpenRequests, cache.CacheHits, cache.CacheMisses, cache.TotalEvictions,
            cache.OwnedEntryCount, cache.ReadyDeltaCount, cache.EstimatedBytes);
        handler->PSendSysMessage(
            "SoloCollections load queries={} rows={} last_us={} max_us={} total_us={} duplicate_grants={} tx_retries={}",
            store.LoadQueryCount, store.LoadedUnlockRows, store.LastLoadMicroseconds,
            store.MaxLoadMicroseconds, store.TotalLoadMicroseconds,
            store.DuplicateGrantRequests, store.TransactionRetryAttempts);
        handler->PSendSysMessage(
            "SoloCollections sc2 sessions={} outbound={} snapshots={} chunks={} payload_bytes={} queue_last_us={} "
            "queue_max_us={} sent_packets={} sent_bytes={} send_last_us={} send_max_us={}",
            protocol.SessionCount, protocol.OutboundPacketCount, protocol.SnapshotTransfers,
            protocol.SnapshotChunks, protocol.SnapshotPayloadBytes,
            protocol.LastSnapshotQueueMicroseconds, protocol.MaxSnapshotQueueMicroseconds,
            protocol.SentPackets, protocol.SentBytes,
            protocol.LastSendMicroseconds, protocol.MaxSendMicroseconds);
        return true;
    }

    static bool HandleBenchmark(ChatHandler* handler)
    {
        constexpr std::size_t BenchmarkEntries = 18'190;
        constexpr std::size_t ShadowSetRows = 509;
        constexpr std::size_t CompanionCandidateRows = 201;
        AppearanceCatalog const& catalog = GetAppearanceCatalog();
        std::vector<AppearanceCollectionDefinition const*> materialized;
        materialized.reserve(BenchmarkEntries);
        auto loadStarted = std::chrono::steady_clock::now();
        auto const& collections = catalog.Collections();
        for (std::size_t index = 0; index < BenchmarkEntries; ++index)
            materialized.push_back(collections.empty() ? nullptr : &collections[index % collections.size()]);
        auto filterStarted = std::chrono::steady_clock::now();
        std::size_t filtered = static_cast<std::size_t>(std::count_if(
            materialized.begin(), materialized.end(), [](AppearanceCollectionDefinition const* definition)
            {
                return definition && definition->DisplayId != 0 && definition->PrimarySourceItemId != 0;
            }));
        auto lookupStarted = std::chrono::steady_clock::now();
        std::size_t found = 0;
        for (AppearanceCollectionDefinition const* definition : materialized)
            if (definition && catalog.Find(definition->Id))
                ++found;
        auto finished = std::chrono::steady_clock::now();
        auto microseconds = [](auto start, auto end)
        {
            return std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
        };
        std::int64_t loadUs = microseconds(loadStarted, filterStarted);
        std::int64_t filterUs = microseconds(filterStarted, lookupStarted);
        std::int64_t lookupUs = microseconds(lookupStarted, finished);
        handler->PSendSysMessage(
            "SoloCollections benchmark scale={} shadow_sets={} companion_candidates={} catalog_entries={} materialized={} filtered={} found={} "
            "load_us={} filter_us={} lookup_us={}",
            BenchmarkEntries, ShadowSetRows, CompanionCandidateRows, collections.size(), materialized.size(), filtered, found,
            loadUs, filterUs, lookupUs);
        LOG_INFO("module.solocollections.performance",
            "event=appearance_catalog_benchmark scale={} shadow_sets={} companion_candidates={} catalog_entries={} materialized={} filtered={} found={} "
            "load_us={} filter_us={} lookup_us={}",
            BenchmarkEntries, ShadowSetRows, CompanionCandidateRows, collections.size(), materialized.size(), filtered, found,
            loadUs, filterUs, lookupUs);
        return true;
    }

    static bool HandleAccount(ChatHandler* handler, Optional<uint32> requestedAccount)
    {
        std::optional<AccountId> accountId = ResolveAccount(handler, requestedAccount);
        if (!accountId)
            return false;
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(*accountId);
        if (!snapshot)
        {
            handler->SendErrorMessage("SoloCollections account {} is not in the online cache.", accountId->Value());
            return true;
        }

        handler->PSendSysMessage(
            "SoloCollections account={} state={} generation={} revision={} sessions={} pending_deltas={} eviction={}",
            accountId->Value(), CacheStateName(snapshot->State), snapshot->Generation.Value(),
            snapshot->Revision.Value(), snapshot->SessionCount, snapshot->PendingDeltaCount,
            snapshot->EvictionScheduled ? "scheduled" : "none");
        return true;
    }

    static bool HandleGrant(
        ChatHandler* handler, uint16 typeValue, uint32 collectionValue, Optional<uint32> requestedAccount)
    {
        return HandleMutation(handler, typeValue, collectionValue, requestedAccount, CollectionMutationKind::Grant);
    }

    static bool HandleRevoke(
        ChatHandler* handler, uint16 typeValue, uint32 collectionValue, Optional<uint32> requestedAccount)
    {
        return HandleMutation(handler, typeValue, collectionValue, requestedAccount, CollectionMutationKind::Revoke);
    }

    static bool HandleMutation(ChatHandler* handler, uint16 typeValue, uint32 collectionValue,
        Optional<uint32> requestedAccount, CollectionMutationKind kind)
    {
        if (!handler->HasPermission(RBAC_SC_WRITE))
        {
            handler->SendErrorMessage("SoloCollections write permission denied.");
            return false;
        }

        std::optional<AccountId> accountId = ResolveAccount(handler, requestedAccount);
        if (!accountId)
            return false;
        CollectionTypeId typeId(typeValue);
        CollectionId collectionId(collectionValue);
        AccountCollectionMutation mutation = BuildGmMutation(handler, *accountId, typeId, collectionId, kind);

        CollectionProviderRegistry& registry = GetCollectionProviderRegistry();
        CollectionProvider const* provider = registry.Find(typeId);
        CollectionProviderRuntimeState const* providerState = registry.State(typeId);
        if (!provider || !providerState)
            return RejectAndAudit(handler, mutation, CollectionReasonCode::UnknownType);
        if (providerState->Mode != CollectionProviderMode::Enabled)
            return RejectAndAudit(handler, mutation, providerState->Mode == CollectionProviderMode::ReadOnly ?
                CollectionReasonCode::ReadOnly : CollectionReasonCode::Disabled);

        CollectionResult catalogResult = provider->Evaluate(collectionId);
        if (!catalogResult.Availability.CatalogKnown)
            return RejectAndAudit(handler, mutation, CollectionReasonCode::UnknownCollection);

        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(*accountId);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return RejectAndAudit(handler, mutation, CollectionReasonCode::NotReady);

        mutation.Generation = snapshot->Generation;
        MutationStartResult started = GetAccountCollectionStore().BeginMutation(mutation);
        if (!started.Accepted)
            return RejectAndAudit(handler, mutation, started.Reason);

        handler->PSendSysMessage(
            "SoloCollections {} queued: account={} type={} collection={} pending_revision={}",
            kind == CollectionMutationKind::Grant ? "grant" : "revoke", accountId->Value(),
            typeId.Value(), collectionId.Value(), started.PendingRevision.Value());
        return true;
    }

    static bool HandleReload(ChatHandler* handler, Optional<uint32> requestedAccount)
    {
        std::optional<AccountId> accountId = ResolveAccount(handler, requestedAccount);
        if (!accountId)
            return false;
        std::uint32_t playerGuid = handler->GetPlayer() &&
            handler->GetSession()->GetAccountId() == accountId->Value() ?
            handler->GetPlayer()->GetGUID().GetCounter() : 0;
        if (!GetAccountCollectionStore().ReloadAccount(*accountId, playerGuid))
        {
            handler->SendErrorMessage(
                "SoloCollections reload rejected; account must be online/idle and database schema ready.");
            return true;
        }
        handler->PSendSysMessage("SoloCollections reload queued for account {}.", accountId->Value());
        return true;
    }

    static bool HandleResync(ChatHandler* handler, Optional<uint32> requestedAccount)
    {
        std::optional<AccountId> accountId = ResolveAccount(handler, requestedAccount);
        if (!accountId)
            return false;
        if (!GetAccountCollectionStore().RequestResync(*accountId))
        {
            handler->SendErrorMessage(
                "SoloCollections resync unavailable; account must be ready and an SC2 event sink must be registered.");
            return true;
        }
        handler->PSendSysMessage("SoloCollections resync requested for account {}.", accountId->Value());
        return true;
    }

    static bool HandleImport(ChatHandler* handler, Tail arguments)
    {
        return HandleDryRun(handler, "import", arguments);
    }

    static bool HandleReconcile(ChatHandler* handler, Tail arguments)
    {
        return HandleDryRun(handler, "reconcile", arguments);
    }

    static bool HandleDryRun(ChatHandler* handler, std::string_view operation, Tail arguments)
    {
        std::vector<std::string_view> tokens = Acore::Tokenize(arguments, ' ', false);
        if (tokens.empty() || tokens[0] != "--dry-run" || tokens.size() > 2)
        {
            handler->SendErrorMessage("Usage: .solocollections {} --dry-run [account_id]", operation);
            return false;
        }

        Optional<uint32> requestedAccount;
        if (tokens.size() == 2)
        {
            requestedAccount = Acore::StringTo<uint32>(tokens[1]);
            if (!requestedAccount || *requestedAccount == 0)
            {
                handler->SendErrorMessage("Invalid numeric account ID.");
                return false;
            }
        }
        std::optional<AccountId> accountId = ResolveAccount(handler, requestedAccount);
        if (!accountId)
            return false;
        if (!GetAccountCollectionStore().IsSchemaReady())
        {
            handler->SendErrorMessage("SoloCollections database schema is not ready; dry-run aborted.");
            return true;
        }

        AppearanceMigrationReport report = GetAppearanceService().BuildMigrationDryRun(*accountId);
        if (!report.Ready)
        {
            handler->SendErrorMessage("SoloCollections {} dry-run appearance repository is not ready.", operation);
            return true;
        }
        handler->PSendSysMessage(
            "SoloCollections {} dry-run account={} legacy={} valid={} canonical={} merged={} unknown={} "
            "disabled={} missing_template={} conflicts={} writes=0",
            operation, accountId->Value(), report.LegacySources, report.ValidSources,
            report.CanonicalGroups, report.MergedSources, report.UnknownSources,
            report.DisabledSources, report.MissingTemplates, report.Conflicts);
        return true;
    }
};
}
}

void AddSC_solo_collections_commands()
{
    new SoloCollections::SoloCollectionsCommandScript();
}
