# Log collection with the Fluent Bit and the OTEL Collector

Collect logs and store in ClickHouse using the Fluent Bit as an agent and the OTEL Collector as a gateway.

Installs the OTEL Collector as a deployment (for an aggregator) and an Fluent Bit as a deamonset to collect logs from each node.

## Under development

Currently this configuration causes Fluent Bit to crash:

[issue](https://github.com/fluent/fluent-bit/issues/6512#issuecomment-1366003651)

```bash
[2022/12/27 15:48:18] [engine] caught signal (SIGSEGV)
#0  0x562f598f3c94      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:713
#1  0x562f598f36b0      in  required_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:455
#2  0x562f598f3951      in  unlabeled_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:593
#3  0x562f598f3dc6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:739
#4  0x562f598f3bfd      in  repeated_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:675
#5  0x562f598f3de6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:744
#6  0x562f598f36b0      in  required_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:455
#7  0x562f598f376f      in  oneof_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:492
#8  0x562f598f3d77      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:727
#9  0x562f598f36b0      in  required_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:455
#10 0x562f598f3951      in  unlabeled_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:593
#11 0x562f598f3dc6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:739
#12 0x562f598f3bfd      in  repeated_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:675
#13 0x562f598f3de6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:744
#14 0x562f598f36b0      in  required_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:455
#15 0x562f598f376f      in  oneof_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:492
#16 0x562f598f3d77      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:727
#17 0x562f598f36b0      in  required_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:455
#18 0x562f598f3951      in  unlabeled_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:593
#19 0x562f598f3dc6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:739
#20 0x562f598f3bfd      in  repeated_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:675
#21 0x562f598f3de6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:744
#22 0x562f598f3bfd      in  repeated_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:675
#23 0x562f598f3de6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:744
#24 0x562f598f3bfd      in  repeated_field_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:675
#25 0x562f598f3de6      in  protobuf_c_message_get_packed_size() at lib/fluent-otel-proto/proto_c/protobuf-c/protobuf-c.c:744
#26 0x562f598fb9b6      in  opentelemetry__proto__collector__logs__v1__export_logs_service_request__get_packed_size() at lib/fluent-otel-proto/proto_c/opentelemetry/proto/collector/logs/v1/logs_service.pb-c.c:20
#27 0x562f59737c88      in  flush_to_otel() at plugins/out_opentelemetry/opentelemetry.c:671
#28 0x562f597380b9      in  process_logs() at plugins/out_opentelemetry/opentelemetry.c:794
#29 0x562f59738df1      in  cb_opentelemetry_flush() at plugins/out_opentelemetry/opentelemetry.c:1029
#30 0x562f5934f4a0      in  output_pre_cb_flush() at include/fluent-bit/flb_output.h:527
#31 0x562f59d92266      in  co_init() at lib/monkey/deps/flb_libco/amd64.c:117
#32 0xffffffffffffffff  in  ???() at ???:0
```

We will update this configuration once this issue is resolved.
