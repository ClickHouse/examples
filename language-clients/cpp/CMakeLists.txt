cmake_minimum_required(VERSION 3.16)
project(client_tour CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# WITH_OPENSSL must be set before MakeAvailable: it is what compiles base/sslsocket.cpp
# into the library and makes ClientOptions::SetSSLOptions() usable instead of throwing.
set(WITH_OPENSSL ON CACHE BOOL "Enable OpenSSL in clickhouse-cpp" FORCE)

FetchContent_Declare(
    clickhouse-cpp
    GIT_REPOSITORY https://github.com/ClickHouse/clickhouse-cpp.git
    GIT_TAG        v2.6.2
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(clickhouse-cpp)

add_executable(client_tour main.cpp)
target_link_libraries(client_tour PRIVATE clickhouse-cpp-lib)

# clickhouse/types/types.h includes <absl/numeric/int128.h>. The vendored absl is put on
# the include path with a directory-scoped include_directories() inside clickhouse-cpp,
# so consumers have to add it themselves.
target_include_directories(client_tour PRIVATE "${clickhouse-cpp_SOURCE_DIR}/contrib/absl")
