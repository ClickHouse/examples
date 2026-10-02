#include "validation.hpp"
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>
static void require(bool truth) {
    if (!truth)
        throw std::runtime_error("assertion failed");
}
static void rejects(const std::function<void()> &fn) {
    try {
        fn();
    } catch (const ApiError &) {
        return;
    }
    throw std::runtime_error("expected validation rejection");
}
int main() {
    const std::string valid =
        R"({"sample_id":"ABCDEF00-1234-4567-890A-123456789ABC","sequence":"9007199254740993","reading":-12,"observed_at":"2026-10-02T12:13:14Z"})";
    auto value = parseSample(valid);
    require(value.sampleId == "abcdef00-1234-4567-890a-123456789abc");
    require(value.sequence == 9007199254740993LL && value.reading == -12);
    for (const std::string reading : {"true", "1.0", "1.5", "1000001", "-1000001", "null"})
        rejects([&] {
            parseSample("{\"sample_id\":\"abcdef00-1234-4567-890a-123456789abc\",\"sequence\":"
                        "\"1\",\"reading\":" +
                        reading + "}");
        });
    for (const std::string sequence :
         std::vector<std::string>{"0", "01", "-1", "9223372036854775808", std::string(1000, '9')})
        rejects([&] { decimal(sequence); });
    require(decimal("9223372036854775807") == INT64_MAX);
    rejects([&] {
        parseSample(
            R"({"sample_id":"abcdef00-1234-4567-890a-123456789abc","sequence":"1","reading":1,"reading":2})");
    });
    rejects([&] {
        parseSample(
            R"({"sample_id":"abcdef00-1234-4567-890a-123456789abc","sequence":"1","reading":1,"project":"south"})");
    });
    rejects([&] { parseSample(R"({"sample_id":"\ud800","sequence":"1","reading":1})"); });
    rejects([&] {
        parseSample(
            R"({"sample_id":"abcdef00-1234-4567-890a-123456789abc","sequence":"1","reading":1,"observed_at":"2025-02-29T00:00:00Z"})");
    });
    rejects([&] {
        parseSample(
            R"({"sample_id":"abcdef00-1234-4567-890a-123456789abc","sequence":"1","reading":1,})");
    });
    require(equalToken("same-token", "same-token"));
    require(!equalToken("same-token", "bad-token!"));
    require(pageLimit("100") == 100);
    rejects([&] { pageLimit("101"); });
    rejects([&] { identifier("device\n"); });
    rejects([&] { identifier(std::string("device\0", 7)); });
    std::cout << "3 validation groups passed: canonical payload, numeric bounds, parser/calendar "
                 "boundaries\n";
}
