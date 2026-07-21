#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsProtocol.h"
#include "SoloCollectionsProtocolServer.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace SC = SoloCollections;

namespace
{
void Require(bool condition, std::string const& message)
{
    if (!condition)
        throw std::runtime_error(message);
}

SC::AccountId Account(std::uint32_t value) { return SC::AccountId(value); }
SC::AccountSessionId Session(std::uint64_t value) { return SC::AccountSessionId(value); }

void TestGoldenCodecVectors()
{
    std::vector<std::string> packets {
        "H|1|fedcba9876543210|0.2.0-dev|2026.07.19|local-1",
        "A|1|0123456789abcdef|42|0000001f|2026.07.19|local-1|phase5-dev|5",
        "M|0123456789abcdef|1|bb891f9c9fdf5a4f795488cc49a3a1ed73bfe4e985116be5e6b3aa07b9af53ac",
        "B|0123456789abcdef|17|1|1|42|179c036b|14",
        "C|0123456789abcdef|17|1|1,2,z,10,1z,2s",
        "E|0123456789abcdef|17|179c036b",
        "D|0123456789abcdef|2|43|A|1001",
        "Q|0123456789abcdef|99|1|1001|SUMMON|-",
        "Q|0123456789abcdef|101|10|100001|PREVIEW|-",
        "R|0123456789abcdef|99|LOADING|1|1001|43",
        "R|0123456789abcdef|100|DISMISSED|11|100281|43",
        "R|0123456789abcdef|101|ACCEPTED|10|100001|43",
        "R|0123456789abcdef|102|CATALOG_MISMATCH|10|100001|43",
        "R|0123456789abcdef|103|ASSET_MISMATCH|11|100281|43",
        "S|0123456789abcdef|REVISION_GAP|0|43",
        "X|0123456789abcdef|99|REPLAYED_REQUEST",
    };
    for (std::string const& packet : packets)
    {
        SC::Sc2DecodeResult decoded = SC::DecodeSc2Body(packet);
        Require(decoded.Success, "golden packet did not decode: " + packet);
        Require(SC::EncodeSc2Message(decoded.Message) == packet, "golden packet did not round trip");
        Require(packet.size() <= SC::Sc2Limits::MaxBodyBytes, "golden packet exceeded body limit");
    }
    Require(SC::Sc2Adler32Hex("-") == "002e002e", "empty checksum vector changed");
    Require(SC::Sc2Adler32Hex("1,2,z,10,1z,2s") == "179c036b", "payload checksum vector changed");

    for (std::string const& invalid : {
        "H|1|ABCDEF0123456789|dev|1|1",
        "D|0123456789abcdef|1|0002|A|1",
        "C|0123456789abcdef|1|1|bad payload",
        "Z|1",
    })
        Require(!SC::DecodeSc2Body(invalid).Success, "invalid packet was accepted: " + invalid);
}

SC::Sc2Server BuildServer(SC::AccountCollectionCache& cache)
{
    return SC::Sc2Server(cache, "2026.07.20.1", "wotlk-3.3.5a-local-1", "phase5-dev", {
        { SC::CollectionTypeId(std::uint16_t { 1 }), "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945", true },
    });
}

void TestLoadingIsNotAnEmptySnapshot()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(1), Session(100), 0);
    Require(opened.Accepted, "cache fixture did not open");
    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(1), Session(100));
    Require(server.HandleInbound(Session(100), "H|1|fedcba9876543210|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0),
        "HELLO was not consumed");
    std::vector<std::string> outbound = server.DrainOutbound(Session(100), 32);
    Require(outbound.size() == 3, "loading handshake should emit ACK, mapping and LOADING");
    Require(outbound[0].starts_with("A|"), "HELLO_ACK missing");
    Require(outbound[1].starts_with("M|"), "category mapping missing");
    Require(outbound[2].ends_with("|LOADING"), "loading account was represented as empty owned");
    for (std::string const& packet : outbound)
        Require(!packet.starts_with("B|"), "loading account emitted a snapshot");
}

void TestReadySnapshotIsQueuedAndBounded()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(2), Session(200), 0);
    Require(cache.CompleteLoad(Account(2), opened.Generation,
        { { SC::CollectionTypeId(std::uint16_t { 1 }), SC::CollectionId(std::uint32_t { 1 }) },
          { SC::CollectionTypeId(std::uint16_t { 1 }), SC::CollectionId(std::uint32_t { 71 }) } },
        SC::CollectionRevision(std::uint64_t { 9 })), "cache fixture did not become ready");
    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(2), Session(200));
    (void)server.HandleInbound(Session(200), "H|1|1111111111111111|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 10);
    std::vector<std::string> firstTick = server.DrainOutbound(Session(200), SC::Sc2Limits::MaxPacketsPerTick);
    Require(firstTick.size() == SC::Sc2Limits::MaxPacketsPerTick, "first tick did not honor packet budget");
    std::vector<std::string> rest = server.DrainOutbound(Session(200), 32);
    firstTick.insert(firstTick.end(), rest.begin(), rest.end());
    Require(firstTick.size() == 5, "ready handshake should emit ACK, mapping and a three-packet snapshot");
    Require(firstTick[2].starts_with("B|"), "snapshot begin missing");
    Require(firstTick[3].find("|1,1z") != std::string::npos, "owned payload was not canonical base36");
    Require(firstTick[4].starts_with("E|"), "snapshot end missing");
    for (std::string const& packet : firstTick)
        Require(packet.size() <= SC::Sc2Limits::MaxBodyBytes, "server queued oversized packet");
}

void TestReplayOldNonceAndRateLimit()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(3), Session(300), 0);
    Require(cache.CompleteLoad(Account(3), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "cache fixture did not become ready");
    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(3), Session(300));
    (void)server.HandleInbound(Session(300), "H|1|2222222222222222|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0);
    (void)server.DrainOutbound(Session(300), 32);
    std::string nonce = server.SessionNonce(Session(300));
    Require(nonce.size() == 16, "session nonce was not established");

    std::string request = "Q|" + nonce + "|7|1|1|SUMMON|-";
    Require(server.HandleInbound(Session(300), request, 1), "action request was not consumed");
    Require(server.HandleInbound(Session(300), request, 2), "replayed action request was not consumed");
    std::vector<std::string> replay = server.DrainOutbound(Session(300), 32);
    Require(replay.size() == 2 && replay[0].find("|UNSUPPORTED|") != std::string::npos &&
        replay[1].ends_with("|REPLAYED_REQUEST"), "action replay cache did not reject duplicate requestId");

    Require(server.HandleInbound(Session(300), "S|0000000000000000|CLIENT_REQUEST|0|1", 3),
        "old nonce packet was not consumed");
    Require(server.DrainOutbound(Session(300), 32).empty(), "old nonce produced output or changed state");

    for (int index = 0; index < 40; ++index)
        (void)server.HandleInbound(Session(300), "S|" + nonce + "|CLIENT_REQUEST|0|1", 4);
    std::vector<std::string> limited = server.DrainOutbound(Session(300), 256);
    bool sawRateLimit = false;
    for (std::string const& packet : limited)
        sawRateLimit = sawRateLimit || packet.ends_with("|RATE_LIMITED");
    Require(sawRateLimit, "token bucket never rate limited a burst");
}

void TestAuthoritativeActionHandler()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(4), Session(400), 0);
    Require(cache.CompleteLoad(Account(4), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 9 })),
        "action cache fixture did not become ready");
    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(4), Session(400));
    (void)server.HandleInbound(Session(400), "H|1|3333333333333333|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0);
    (void)server.DrainOutbound(Session(400), 32);
    std::string nonce = server.SessionNonce(Session(400));
    bool called = false;
    SC::Sc2Server::ActionHandler handler = [&called](SC::AccountId account, SC::Sc2Message const& request)
    {
        called = true;
        Require(account == Account(4), "action handler account was not server-derived");
        Require(request.TypeId == 10 && request.CollectionId == 100001 && request.ActionId == "SUMMON" &&
            request.Target == "-", "action handler received altered logical request fields");
        return std::string("ACCEPTED");
    };
    std::string request = "Q|" + nonce + "|8|10|100001|SUMMON|-";
    Require(server.HandleInbound(Session(400), request, 1, handler), "authoritative action was not consumed");
    std::vector<std::string> result = server.DrainOutbound(Session(400), 32);
    Require(called && result.size() == 1 && result[0].find("|ACCEPTED|10|100001|9") != std::string::npos,
        "authoritative action result was not correlated to the logical collection");

    SC::Sc2Server::ActionHandler dismiss = [](SC::AccountId, SC::Sc2Message const&)
    {
        return std::string("DISMISSED");
    };
    request = "Q|" + nonce + "|9|10|100001|SUMMON|-";
    Require(server.HandleInbound(Session(400), request, 2, dismiss), "dismiss action was not consumed");
    result = server.DrainOutbound(Session(400), 32);
    Require(result.size() == 1 && result[0].find("|DISMISSED|10|100001|9") != std::string::npos,
        "successful companion toggle status was rejected by the protocol");
}

void TestPreviewVersionGatesAndUnownedDispatch()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(9), Session(900), 0);
    Require(cache.CompleteLoad(Account(9), opened.Generation, {}, SC::CollectionRevision(21)),
        "preview cache fixture did not become ready");

    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(9), Session(900));
    (void)server.HandleInbound(Session(900),
        "H|1|9999999999999900|0.2.0-dev|stale-metadata|wotlk-3.3.5a-local-1", 0);
    (void)server.DrainOutbound(Session(900), 32);
    std::string nonce = server.SessionNonce(Session(900));
    bool called = false;
    SC::Sc2Server::ActionHandler handler = [&called](SC::AccountId, SC::Sc2Message const& request)
    {
        called = true;
        return request.ActionId == "PREVIEW" ? std::string("ACCEPTED") : std::string("NOT_OWNED");
    };
    (void)server.HandleInbound(Session(900),
        "Q|" + nonce + "|1|10|100001|PREVIEW|-", 1, handler);
    std::vector<std::string> result = server.DrainOutbound(Session(900), 32);
    Require(!called && result.size() == 1 && result[0].find("|CATALOG_MISMATCH|") != std::string::npos,
        "stale metadata reached an action handler");

    server.CloseSession(Session(900));
    server.OpenSession(Account(9), Session(900));
    (void)server.HandleInbound(Session(900),
        "H|1|9999999999999901|0.2.0-dev|2026.07.20.1|wrong-asset-pack", 10);
    (void)server.DrainOutbound(Session(900), 32);
    nonce = server.SessionNonce(Session(900));
    called = false;
    (void)server.HandleInbound(Session(900),
        "Q|" + nonce + "|2|11|100281|PREVIEW|-", 11, handler);
    result = server.DrainOutbound(Session(900), 32);
    Require(!called && result.size() == 1 && result[0].find("|ASSET_MISMATCH|") != std::string::npos,
        "preview asset mismatch reached an action handler");

    (void)server.HandleInbound(Session(900),
        "Q|" + nonce + "|3|11|100281|SUMMON|-", 12, handler);
    result = server.DrainOutbound(Session(900), 32);
    Require(called && result.size() == 1 && result[0].find("|NOT_OWNED|") != std::string::npos,
        "asset mismatch incorrectly disabled owned-gated non-preview actions");

    server.CloseSession(Session(900));
    server.OpenSession(Account(9), Session(900));
    (void)server.HandleInbound(Session(900),
        "H|1|9999999999999902|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 20);
    (void)server.DrainOutbound(Session(900), 32);
    nonce = server.SessionNonce(Session(900));
    called = false;
    (void)server.HandleInbound(Session(900),
        "Q|" + nonce + "|4|10|100001|PREVIEW|-", 21, handler);
    result = server.DrainOutbound(Session(900), 32);
    Require(called && result.size() == 1 && result[0].find("|ACCEPTED|") != std::string::npos,
        "unowned preview was not dispatched through the shared SC2 action path");
}

void TestAccountScopedDeltaFanout()
{
    SC::AccountCollectionCache cache;
    auto first = cache.OpenSession(Account(5), Session(500), 0);
    (void)cache.OpenSession(Account(5), Session(501), 0);
    auto isolated = cache.OpenSession(Account(6), Session(600), 0);
    Require(cache.CompleteLoad(Account(5), first.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "shared-account cache fixture did not become ready");
    Require(cache.CompleteLoad(Account(6), isolated.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "isolated-account cache fixture did not become ready");

    SC::Sc2Server server = BuildServer(cache);
    server.OpenSession(Account(5), Session(500));
    server.OpenSession(Account(5), Session(501));
    server.OpenSession(Account(6), Session(600));
    (void)server.HandleInbound(Session(500),
        "H|1|5555555555555500|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0);
    (void)server.HandleInbound(Session(501),
        "H|1|5555555555555501|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0);
    (void)server.HandleInbound(Session(600),
        "H|1|6666666666666600|0.2.0-dev|2026.07.20.1|wotlk-3.3.5a-local-1", 0);
    (void)server.DrainOutbound(Session(500), 32);
    (void)server.DrainOutbound(Session(501), 32);
    (void)server.DrainOutbound(Session(600), 32);

    SC::CollectionDelta delta {
        { SC::CollectionTypeId(std::uint16_t { 1 }), SC::CollectionId(std::uint32_t { 42 }) },
        SC::CollectionDeltaKind::Unlock, SC::CollectionRevision(std::uint64_t { 2 })
    };
    server.OnCollectionDeltaCommitted(Account(5), delta);

    std::vector<std::string> firstSession = server.DrainOutbound(Session(500), 32);
    std::vector<std::string> secondSession = server.DrainOutbound(Session(501), 32);
    std::vector<std::string> otherAccount = server.DrainOutbound(Session(600), 32);
    Require(firstSession.size() == 1 && firstSession[0].starts_with("D|") &&
        firstSession[0].find("|1|2|A|42") != std::string::npos,
        "first session did not receive its account delta");
    Require(secondSession.size() == 1 && secondSession[0].starts_with("D|") &&
        secondSession[0].find("|1|2|A|42") != std::string::npos,
        "second same-account session did not receive the account delta");
    Require(otherAccount.empty(), "collection delta leaked to a different account");
}

void TestSyntheticPersistedProviderRevisionSync()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(77), Session(770), 0);
    Require(cache.CompleteLoad(Account(77), opened.Generation, {}, SC::CollectionRevision(10)),
        "synthetic persisted provider cache did not become ready");
    SC::Sc2Server server(cache, "2026.07.20.2", "wotlk-3.3.5a-local-1", "phase10-provider", {
        { SC::CollectionTypeId(std::uint16_t { 31 }),
          "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945", true },
    });
    server.OpenSession(Account(77), Session(770));
    (void)server.HandleInbound(Session(770),
        "H|1|7777777777777777|0.2.0-dev|2026.07.20.2|wotlk-3.3.5a-local-1", 0);
    (void)server.DrainOutbound(Session(770), 32);

    SC::CollectionDelta unlock {
        { SC::CollectionTypeId(std::uint16_t { 31 }), SC::CollectionId(std::uint32_t { 310001 }) },
        SC::CollectionDeltaKind::Unlock, SC::CollectionRevision(std::uint64_t { 11 })
    };
    Require(cache.QueueDelta(Account(77), unlock) == SC::DeltaQueueResult::Applied,
        "synthetic persisted provider delta did not update the account cache");
    server.OnCollectionDeltaCommitted(Account(77), unlock);
    std::vector<std::string> outbound = server.DrainOutbound(Session(770), 32);
    Require(outbound.size() == 1 && outbound[0].starts_with("D|") &&
        outbound[0].find("|31|11|A|310001") != std::string::npos,
        "synthetic persisted provider did not reuse revisioned SC2 delta sync");
}

void TestExternalTitleSnapshotsAreSessionScoped()
{
    SC::AccountCollectionCache cache;
    auto opened = cache.OpenSession(Account(88), Session(880), 0);
    (void)cache.OpenSession(Account(88), Session(881), 0);
    Require(cache.CompleteLoad(Account(88), opened.Generation, {}, SC::CollectionRevision(12)),
        "external title cache fixture did not become ready");
    SC::Sc2Server server(cache, "2026.07.20.3", "wotlk-3.3.5a-local-1", "phase10-title", {
        { SC::CollectionTypeId(std::uint16_t { 15 }),
          "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945", true, true },
    });
    server.OpenSession(Account(88), Session(880));
    server.OpenSession(Account(88), Session(881));
    server.SetExternalOwned(Session(880), SC::CollectionTypeId(std::uint16_t { 15 }), {
        SC::CollectionId(5), SC::CollectionId(1), SC::CollectionId(5)
    });
    (void)server.HandleInbound(Session(880),
        "H|1|8888888888888880|0.2.0-dev|2026.07.20.3|wotlk-3.3.5a-local-1", 0);
    (void)server.HandleInbound(Session(881),
        "H|1|8888888888888881|0.2.0-dev|2026.07.20.3|wotlk-3.3.5a-local-1", 0);
    std::vector<std::string> owned = server.DrainOutbound(Session(880), 32);
    std::vector<std::string> empty = server.DrainOutbound(Session(881), 32);
    bool sawOwnedPayload = false;
    bool sawEmptyPayload = false;
    for (std::string const& packet : owned)
        sawOwnedPayload = sawOwnedPayload || packet.find("|1,5") != std::string::npos;
    for (std::string const& packet : empty)
        sawEmptyPayload = sawEmptyPayload || packet.ends_with("|-");
    Require(sawOwnedPayload, "external title ownership was not sorted, deduplicated and snapshotted");
    Require(sawEmptyPayload, "external title ownership leaked between character sessions");
}
}

int main()
{
    try
    {
        TestGoldenCodecVectors();
        TestLoadingIsNotAnEmptySnapshot();
        TestReadySnapshotIsQueuedAndBounded();
        TestReplayOldNonceAndRateLimit();
        TestAuthoritativeActionHandler();
        TestPreviewVersionGatesAndUnownedDispatch();
        TestAccountScopedDeltaFanout();
        TestSyntheticPersistedProviderRevisionSync();
        TestExternalTitleSnapshotsAreSessionScoped();
        std::cout << "SoloCollections SC2 protocol tests passed" << std::endl;
        return EXIT_SUCCESS;
    }
    catch (std::exception const& exception)
    {
        std::cerr << exception.what() << std::endl;
        return EXIT_FAILURE;
    }
}
