#include "validation.hpp"
#include <algorithm>
#include <charconv>
#include <chrono>
#include <memory>
#include <openssl/crypto.h>
#include <regex>
#include <set>

std::string identifier(const std::string &text) {
    static const std::regex expression("[a-z][a-z0-9-]{0,31}");
    if (text.size() > 32 || !std::regex_match(text, expression))
        throw ApiError(400, "invalid_identifier");
    return text;
}
std::string uuid(const std::string &text) {
    static const std::regex expression(
        "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    if (text.size() != 36 || !std::regex_match(text, expression))
        throw ApiError(400, "invalid_sample_id");
    auto result = text;
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char c) {
        return static_cast<char>(c >= 'A' && c <= 'F' ? c + ('a' - 'A') : c);
    });
    return result;
}
int64_t decimal(const std::string &text) {
    if (text.empty() || text.size() > 19 || text[0] == '0' ||
        !std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; }))
        throw ApiError(400, "invalid_sequence");
    int64_t result = 0;
    auto converted = std::from_chars(text.data(), text.data() + text.size(), result);
    if (converted.ec != std::errc() || converted.ptr != text.data() + text.size())
        throw ApiError(400, "invalid_sequence");
    return result;
}
static std::string observation(const std::string &text) {
    static const std::regex expression("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z");
    if (text.size() != 20 || !std::regex_match(text, expression))
        throw ApiError(400, "invalid_observed_at");
    auto number = [&text](size_t at, size_t count) { return std::stoi(text.substr(at, count)); };
    const int y = number(0, 4);
    const auto date = std::chrono::year_month_day{
        std::chrono::year{y}, std::chrono::month{static_cast<unsigned>(number(5, 2))},
        std::chrono::day{static_cast<unsigned>(number(8, 2))}};
    if (y < 1970 || y > 2100 || !date.ok() || number(11, 2) > 23 || number(14, 2) > 59 ||
        number(17, 2) > 59)
        throw ApiError(400, "invalid_observed_at");
    return text;
}
SampleInput parseSample(std::string_view body) {
    if (body.size() > 4096)
        throw ApiError(413, "body_too_large");
    Json::CharReaderBuilder builder;
    builder["rejectDupKeys"] = true;
    builder["failIfExtra"] = true;
    builder["allowComments"] = false;
    builder["allowTrailingCommas"] = false;
    builder["strictRoot"] = true;
    std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    Json::Value value;
    std::string errors;
    if (!reader->parse(body.data(), body.data() + body.size(), &value, &errors) ||
        !value.isObject())
        throw ApiError(400, "invalid_json");
    const std::set<std::string> fields{"sample_id", "sequence", "reading", "observed_at"};
    for (const auto &name : value.getMemberNames())
        if (!fields.count(name))
            throw ApiError(400, "invalid_fields");
    if (!value["sample_id"].isString() || !value["sequence"].isString())
        throw ApiError(400, "invalid_fields");
    const auto &reading = value["reading"];
    if (reading.type() != Json::intValue && reading.type() != Json::uintValue)
        throw ApiError(400, "invalid_reading");
    if (!reading.isInt64() || reading.asInt64() < -1000000 || reading.asInt64() > 1000000)
        throw ApiError(400, "invalid_reading");
    std::optional<std::string> observed;
    if (value.isMember("observed_at") && !value["observed_at"].isNull()) {
        if (!value["observed_at"].isString())
            throw ApiError(400, "invalid_observed_at");
        observed = observation(value["observed_at"].asString());
    }
    return {uuid(value["sample_id"].asString()), decimal(value["sequence"].asString()),
            static_cast<int>(reading.asInt64()), observed};
}
int pageLimit(const std::string &text) {
    if (text.empty())
        return 25;
    if (text.size() > 3)
        throw ApiError(400, "invalid_limit");
    int result = 0;
    auto converted = std::from_chars(text.data(), text.data() + text.size(), result);
    if (converted.ec != std::errc() || converted.ptr != text.data() + text.size() || result < 1 ||
        result > 100)
        throw ApiError(400, "invalid_limit");
    return result;
}
bool equalToken(const std::string &left, const std::string &right) {
    if (left.size() != right.size())
        return false;
    return CRYPTO_memcmp(left.data(), right.data(), left.size()) == 0;
}
