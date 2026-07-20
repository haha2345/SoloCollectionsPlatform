cmake_minimum_required(VERSION 3.20)
project(SoloCollectionsDomainTests LANGUAGES CXX)

enable_testing()

add_executable(solo_collections_domain_tests
    SoloCollectionsDomainTests.cpp
    ../../src/SoloCollectionsAccountCache.cpp
    ../../src/SoloCollectionsCompanionCatalog.cpp
    ../../src/SoloCollectionsEligibility.cpp
    ../../src/SoloCollectionsIdentity.cpp
    ../../src/SoloCollectionsMountCatalog.cpp
    ../../src/SoloCollectionsProvider.cpp
    ../../src/SoloCollectionsShadowComparison.cpp
    ../../src/SoloCollectionsToyCatalog.cpp
)

target_include_directories(solo_collections_domain_tests PRIVATE ../../src)
target_compile_features(solo_collections_domain_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(solo_collections_domain_tests PRIVATE /W4 /WX /permissive-)
else()
    target_compile_options(solo_collections_domain_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME solo_collections_domain_tests COMMAND solo_collections_domain_tests)

add_executable(solo_collections_protocol_tests
    SoloCollectionsProtocolTests.cpp
    ../../src/SoloCollectionsAccountCache.cpp
    ../../src/SoloCollectionsProtocol.cpp
    ../../src/SoloCollectionsProtocolServer.cpp
)

target_include_directories(solo_collections_protocol_tests PRIVATE ../../src)
target_compile_features(solo_collections_protocol_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(solo_collections_protocol_tests PRIVATE /W4 /WX /permissive-)
else()
    target_compile_options(solo_collections_protocol_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME solo_collections_protocol_tests COMMAND solo_collections_protocol_tests)
