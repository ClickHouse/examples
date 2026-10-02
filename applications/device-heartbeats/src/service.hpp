#pragma once
#include "validation.hpp"
#include <atomic>
#include <drogon/drogon.h>
#include <drogon/orm/DbClient.h>
#include <functional>
#include <memory>

using Reply = std::function<void(const drogon::HttpResponsePtr &)>;
drogon::HttpResponsePtr jsonResponse(int status, const Json::Value &value);
class Service {
    drogon::orm::DbClientPtr client_;
    std::shared_ptr<std::atomic<int>> active_;

  public:
    explicit Service(drogon::orm::DbClientPtr client);
    void submit(const std::string &project, const std::string &device, SampleInput input,
                Reply reply);
    void devices(const std::string &project, int limit, const std::string &after, Reply reply);
    void history(const std::string &project, const std::string &device, int limit, int64_t before,
                 Reply reply);
};
