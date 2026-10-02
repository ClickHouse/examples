#pragma once
#include <cstdint>
#include <json/json.h>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

struct ApiError : std::runtime_error {
    int status;
    ApiError(int status, const std::string &code) : std::runtime_error(code), status(status) {}
};
struct SampleInput {
    std::string sampleId;
    int64_t sequence;
    int reading;
    std::optional<std::string> observedAt;
};
std::string identifier(const std::string &text);
std::string uuid(const std::string &text);
int64_t decimal(const std::string &text);
SampleInput parseSample(std::string_view body);
int pageLimit(const std::string &text);
bool equalToken(const std::string &left, const std::string &right);
