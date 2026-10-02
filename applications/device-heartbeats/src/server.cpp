#include "service.hpp"
#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <regex>
#include <set>

static std::string required(const char *name) {
    const auto value = std::getenv(name);
    if (!value || !*value)
        throw std::runtime_error(std::string("Missing ") + name);
    return value;
}
static std::string quoted(const std::string &value) {
    std::string result = "'";
    for (char c : value) {
        if (c == '\\' || c == '\'')
            result += '\\';
        result += c;
    }
    return result + "'";
}
static std::string connectionInfo() {
    std::string result;
    for (const auto &[option, env] :
         std::map<std::string, std::string>{{"host", "PGHOST"},
                                            {"port", "PGPORT"},
                                            {"dbname", "PGDATABASE"},
                                            {"user", "PGUSER"},
                                            {"password", "PGPASSWORD"},
                                            {"sslrootcert", "PGSSLROOTCERT"}})
        result += option + "=" + quoted(required(env.c_str())) + " ";
    return result + "sslmode=verify-full connect_timeout=5 application_name=device-heartbeats "
                    "options='-c statement_timeout=4000 -c lock_timeout=2000 -c "
                    "idle_in_transaction_session_timeout=6000'";
}
static Json::Value error(const std::string &code) {
    Json::Value body;
    body["error"] = code;
    return body;
}
static void queryFields(const drogon::HttpRequestPtr &request,
                        const std::set<std::string> &allowed) {
    for (const auto &[key, value] : request->parameters()) {
        (void)value;
        if (!allowed.count(key))
            throw ApiError(400, "invalid_query");
    }
}
int main(int argc, char **argv) {
    try {
        const bool preflight = argc == 2 && std::string(argv[1]) == "--preflight";
        const bool check = argc == 2 && std::string(argv[1]) == "--check-db";
        if (argc > 1 && !preflight && !check)
            throw std::runtime_error("Unknown option");
        auto &app = drogon::app();
        app.setLogLevel(trantor::Logger::kWarn);
        drogon::orm::DbClientPtr database;
        std::shared_ptr<Service> service;
        if (!preflight) {
            if (required("PGUSER") != "heartbeats_app")
                throw std::runtime_error("Runtime requires heartbeats_app");
            database = drogon::orm::DbClient::newPgClient(connectionInfo(), 4);
            database->setTimeout(5.0);
            // Synchronous startup only; no event loop is blocked by runtime handlers.
            database->execSqlSync("SELECT 1");
            if (check) {
                database->closeAll();
                std::cout << "Verified database connection\n";
                return 0;
            }
            service = std::make_shared<Service>(database);
        }
        int listenPort = 4000;
        if (const auto configured = std::getenv("PORT")) {
            const std::string text = configured;
            if (text.empty() || text.size() > 5 ||
                !std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; }))
                throw std::runtime_error("Invalid PORT");
            listenPort = std::stoi(text);
            if (listenPort < 1024 || listenPort > 65535)
                throw std::runtime_error("Invalid PORT");
        }
        std::map<std::string, std::string> tokens;
        if (!preflight) {
            tokens = {{"north", required("NORTH_TOKEN")}, {"south", required("SOUTH_TOKEN")}};
            const std::regex pattern("[!-~]{32,128}");
            for (const auto &[project, token] : tokens) {
                (void)project;
                if (!std::regex_match(token, pattern))
                    throw std::runtime_error("Invalid project token");
            }
            if (tokens.at("north") == tokens.at("south"))
                throw std::runtime_error("Tokens must differ");
        }
        auto active = std::make_shared<std::atomic<int>>(0);
        auto guarded = [tokens, active](const drogon::HttpRequestPtr &request, Reply reply,
                                        auto operation) {
            std::string project;
            for (const auto &[id, token] : tokens)
                if (equalToken(request->getHeader("authorization"), "Bearer " + token))
                    project = id;
            if (project.empty()) {
                reply(jsonResponse(401, error("unauthorized")));
                return;
            }
            if (active->fetch_add(1) >= 12) {
                --*active;
                reply(jsonResponse(503, error("busy")));
                return;
            }
            auto completed = std::make_shared<std::atomic<bool>>(false);
            Reply finish = [active, completed,
                            reply = std::move(reply)](const drogon::HttpResponsePtr &response) {
                if (!completed->exchange(true)) {
                    --*active;
                    reply(response);
                }
            };
            try {
                operation(project, finish);
            } catch (const ApiError &e) {
                finish(jsonResponse(e.status, error(e.what())));
            } catch (const std::exception &) {
                finish(jsonResponse(500, error("request_failure")));
            }
        };
        app.registerHandler("/health",
                            [](const drogon::HttpRequestPtr &, Reply &&reply) {
                                Json::Value body;
                                body["status"] = "up";
                                reply(jsonResponse(200, body));
                            },
                            {drogon::Get});
        if (service) {
            app.registerHandler(
                "/devices",
                [service, guarded](const drogon::HttpRequestPtr &request, Reply &&reply) {
                    guarded(request, std::move(reply),
                            [&](const std::string &project, Reply finish) {
                                queryFields(request, {"limit", "after"});
                                const auto after = request->getParameter("after");
                                if (!after.empty())
                                    identifier(after);
                                service->devices(project, pageLimit(request->getParameter("limit")),
                                                 after, std::move(finish));
                            });
                },
                {drogon::Get});
            app.registerHandler(
                "/devices/{1}/samples",
                [service, guarded](const drogon::HttpRequestPtr &request, Reply &&reply,
                                   const std::string &device) {
                    guarded(
                        request, std::move(reply), [&](const std::string &project, Reply finish) {
                            identifier(device);
                            if (request->method() == drogon::Post) {
                                queryFields(request, {});
                                auto mediaType = request->getHeader("content-type");
                                mediaType = mediaType.substr(0, mediaType.find(';'));
                                while (!mediaType.empty() &&
                                       (mediaType.back() == ' ' || mediaType.back() == '\t'))
                                    mediaType.pop_back();
                                while (!mediaType.empty() &&
                                       (mediaType.front() == ' ' || mediaType.front() == '\t'))
                                    mediaType.erase(0, 1);
                                std::transform(mediaType.begin(), mediaType.end(),
                                               mediaType.begin(), [](unsigned char c) {
                                                   return static_cast<char>(
                                                       c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
                                               });
                                if (mediaType != "application/json")
                                    throw ApiError(415, "json_required");
                                service->submit(project, device, parseSample(request->body()),
                                                std::move(finish));
                            } else {
                                queryFields(request, {"limit", "before"});
                                const auto before = request->getParameter("before");
                                service->history(
                                    project, device, pageLimit(request->getParameter("limit")),
                                    before.empty() ? 0 : decimal(before), std::move(finish));
                            }
                        });
                },
                {drogon::Get, drogon::Post});
        }
        app.addListener("127.0.0.1", listenPort)
            .setThreadNum(2)
            .setMaxConnectionNum(32)
            .setMaxConnectionNumPerIP(32)
            .setClientMaxBodySize(4096)
            .setClientMaxMemoryBodySize(4096)
            .setIdleConnectionTimeout(10)
            .setKeepaliveRequestsNumber(32)
            .setPipeliningRequestsNumber(4);
        app.run();
        if (database)
            database->closeAll();
        return 0;
    } catch (const std::exception &) {
        std::cerr << "Startup failed; check private configuration and connection diagnostics\n";
        return 1;
    }
}
