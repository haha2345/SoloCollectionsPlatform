#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsProvider.h"

#include "Chat.h"
#include "CommandScript.h"
#include "DatabaseEnv.h"
#include "Player.h"
#include "QueryResult.h"
#include "RBAC.h"
#include "ScriptMgr.h"
#include "StringConvert.h"
#include "Tokenize.h"
#include "WorldSession.h"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

using namespace Acore::ChatCommands;

namespace SoloCollections
{
namespace
{
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

        handler->PSendSysMessage(
            "SoloCollections schema={} providers={}/{}/{} cache_entries={} sessions={} states={}/{}/{} "
            "pending_loads={} pending_mutations={} pending_audits={} pending_deltas={} evictions={}",
            SchemaStateName(store.SchemaState), enabled, readOnly, disabled, cache.EntryCount,
            cache.SessionCount, cache.LoadingCount, cache.ReadyCount, cache.FailedCount,
            store.PendingLoads, store.PendingMutations, store.PendingAudits,
            cache.PendingDeltaCount, cache.EvictionScheduledCount);
        handler->PSendSysMessage(
            "SoloCollections totals loads_ok={} loads_failed={} mutations_ok={} mutations_failed={}",
            store.SuccessfulLoads, store.FailedLoads, store.SuccessfulMutations, store.FailedMutations);
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

        QueryResult result = CharacterDatabase.Query(
            "SELECT "
            "(SELECT COUNT(*) FROM custom_unlocked_appearances WHERE account_id = {}), "
            "(SELECT COUNT(*) FROM sc_collection_unlock WHERE account_id = {})",
            accountId->Value(), accountId->Value());
        if (!result)
        {
            handler->SendErrorMessage("SoloCollections {} dry-run query failed.", operation);
            return true;
        }
        Field* fields = result->Fetch();
        handler->PSendSysMessage(
            "SoloCollections {} dry-run account={} legacy_appearances={} unified_unlocks={} writes=0",
            operation, accountId->Value(), fields[0].Get<uint64>(), fields[1].Get<uint64>());
        return true;
    }
};
}
}

void AddSC_solo_collections_commands()
{
    new SoloCollections::SoloCollectionsCommandScript();
}
