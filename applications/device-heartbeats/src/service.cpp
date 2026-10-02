#include "service.hpp"
#include <utility>
using namespace drogon::orm;

drogon::HttpResponsePtr jsonResponse(int status, const Json::Value &value) {
    auto response = drogon::HttpResponse::newHttpJsonResponse(value);
    response->setStatusCode(static_cast<drogon::HttpStatusCode>(status));
    response->addHeader("Cache-Control", "no-store");
    return response;
}
static Json::Value errorBody(const std::string &code) {
    Json::Value value;
    value["error"] = code;
    return value;
}
static const std::string projection =
    "id::text, sample_id::text, sequence::text, reading, "
    "to_char(observed_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS observed_at, "
    "to_char(received_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') AS received_at";
static Json::Value sampleRow(const Row &row) {
    Json::Value value;
    for (const auto &name : {"id", "sample_id", "sequence", "received_at"})
        value[name] = row[name].as<std::string>();
    value["reading"] = row["reading"].as<int>();
    value["observed_at"] = row["observed_at"].isNull()
                               ? Json::Value()
                               : Json::Value(row["observed_at"].as<std::string>());
    return value;
}
struct Lease {
    std::shared_ptr<std::atomic<int>> active;
    ~Lease() { --*active; }
};
class Write : public std::enable_shared_from_this<Write> {
    std::string project_, device_;
    SampleInput input_;
    Reply reply_;
    std::shared_ptr<Lease> lease_;
    std::shared_ptr<Transaction> transaction_;
    bool responded_ = false;
    Json::Value result_;
    int status_ = 201;
    int64_t latest_ = 0;
    int count_ = 0;

    void finish(int status, const Json::Value &body) {
        if (responded_)
            return;
        responded_ = true;
        reply_(jsonResponse(status, body));
    }
    void reject(int status, const std::string &code) {
        if (transaction_) {
            transaction_->rollback();
            transaction_.reset();
        }
        // Drogon's commit callback is NOT invoked on rollback. Resolve this path independently.
        finish(status, errorBody(code));
    }
    auto onError() {
        return [self = shared_from_this()](const DrogonDbException &) {
            self->reject(503, "retry_sample_id");
        };
    }
    void retained() {
        auto self = shared_from_this();
        transaction_->execSqlAsync(
            "SELECT " + projection +
                " FROM heartbeats.samples WHERE project=$1 AND device=$2 AND sample_id=$3::uuid",
            [self](const Result &rows) {
                if (!rows.empty()) {
                    const auto saved = sampleRow(rows[0]);
                    const auto observed = self->input_.observedAt
                                              ? Json::Value(*self->input_.observedAt)
                                              : Json::Value();
                    if (saved["sequence"].asString() != std::to_string(self->input_.sequence) ||
                        saved["reading"].asInt() != self->input_.reading ||
                        saved["observed_at"] != observed) {
                        self->reject(409, "sample_conflict");
                        return;
                    }
                    self->result_["sample"] = saved;
                    self->result_["replay"] = true;
                    self->status_ = 200;
                    self->releaseForCommit();
                } else if (self->input_.sequence <= self->latest_) {
                    self->reject(409, "stale_sequence");
                } else if (self->count_ >= 200) {
                    self->reject(409, "history_full");
                } else {
                    self->insert();
                }
            },
            onError(), project_, device_, input_.sampleId);
    }
    void insert() {
        auto self = shared_from_this();
        transaction_->execSqlAsync(
            "INSERT INTO heartbeats.samples(project,device,sample_id,sequence,reading,observed_at) "
            "VALUES($1,$2,$3::uuid,$4,$5,NULLIF($6,'')::timestamptz) RETURNING " +
                projection,
            [self](const Result &rows) {
                self->result_["sample"] = sampleRow(rows[0]);
                self->result_["replay"] = false;
                self->update();
            },
            onError(), project_, device_, input_.sampleId, input_.sequence, input_.reading,
            input_.observedAt.value_or(""));
    }
    void update() {
        auto self = shared_from_this();
        transaction_->execSqlAsync(
            "UPDATE heartbeats.devices SET latest_sequence=$3,sample_count=sample_count+1 "
            "WHERE project=$1 AND id=$2",
            [self](const Result &) { self->releaseForCommit(); }, onError(), project_, device_,
            input_.sequence);
    }
    void releaseForCommit() {
        // Break the ownership cycle: transaction owns its commit callback, callback owns this
        // state. Its destructor queues COMMIT. Only that callback can send successful HTTP status.
        transaction_.reset();
    }

  public:
    Write(std::string project, std::string device, SampleInput input, Reply reply,
          std::shared_ptr<Lease> lease)
        : project_(std::move(project)), device_(std::move(device)), input_(std::move(input)),
          reply_(std::move(reply)), lease_(std::move(lease)) {}
    void begin(const std::shared_ptr<Transaction> &transaction) {
        if (!transaction) {
            finish(503, errorBody("pool_timeout"));
            return;
        }
        transaction_ = transaction;
        auto self = shared_from_this();
        transaction_->setCommitCallback([self](bool committed) {
            if (committed)
                self->finish(self->status_, self->result_);
            else
                self->finish(503, errorBody("retry_sample_id"));
        });
        transaction_->execSqlAsync(
            "SELECT latest_sequence::text,sample_count FROM heartbeats.devices WHERE project=$1 "
            "AND id=$2 FOR UPDATE",
            [self](const Result &rows) {
                if (rows.empty()) {
                    self->reject(404, "unknown_device");
                    return;
                }
                self->latest_ = std::stoll(rows[0]["latest_sequence"].as<std::string>());
                self->count_ = rows[0]["sample_count"].as<int>();
                self->retained();
            },
            onError(), project_, device_);
    }
};
Service::Service(DbClientPtr client)
    : client_(std::move(client)), active_(std::make_shared<std::atomic<int>>(0)) {}
void Service::submit(const std::string &project, const std::string &device, SampleInput input,
                     Reply reply) {
    if (active_->fetch_add(1) >= 8) {
        --*active_;
        reply(jsonResponse(503, errorBody("busy")));
        return;
    }
    auto lease = std::make_shared<Lease>();
    lease->active = active_;
    auto state = std::make_shared<Write>(project, device, std::move(input), std::move(reply),
                                         std::move(lease));
    client_->newTransactionAsync(
        [state](const std::shared_ptr<Transaction> &transaction) { state->begin(transaction); });
}
void Service::devices(const std::string &project, int limit, const std::string &after,
                      Reply reply) {
    client_->execSqlAsync(
        "SELECT id,latest_sequence::text,sample_count FROM heartbeats.devices "
        "WHERE project=$1 AND id>$2 ORDER BY id LIMIT $3::integer",
        [reply](const Result &rows) {
            Json::Value result, values(Json::arrayValue);
            for (const auto &row : rows) {
                Json::Value value;
                value["device"] = row["id"].as<std::string>();
                value["latest_sequence"] = row["latest_sequence"].as<std::string>();
                value["sample_count"] = row["sample_count"].as<int>();
                values.append(value);
            }
            result["rows"] = values;
            result["next_after"] =
                values.empty() ? Json::Value() : values[values.size() - 1]["device"];
            reply(jsonResponse(200, result));
        },
        [reply](const DrogonDbException &) {
            reply(jsonResponse(503, errorBody("database_unavailable")));
        },
        project, after, limit);
}
void Service::history(const std::string &project, const std::string &device, int limit,
                      int64_t before, Reply reply) {
    client_->execSqlAsync(
        "SELECT " + projection +
            " FROM heartbeats.samples WHERE project=$1 AND device=$2 "
            "AND ($3::bigint=0 OR id<$3) ORDER BY heartbeats.samples.id DESC LIMIT $4::integer",
        [reply](const Result &rows) {
            Json::Value result, values(Json::arrayValue);
            for (const auto &row : rows)
                values.append(sampleRow(row));
            result["rows"] = values;
            result["next_before"] =
                values.empty() ? Json::Value() : values[values.size() - 1]["id"];
            reply(jsonResponse(200, result));
        },
        [reply](const DrogonDbException &) {
            reply(jsonResponse(503, errorBody("database_unavailable")));
        },
        project, device, before, limit);
}
