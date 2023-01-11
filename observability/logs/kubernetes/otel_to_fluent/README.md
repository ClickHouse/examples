# Log collection with the Open Telemetry Collector and Fluent Bit

Collect logs and store in ClickHouse using the Open Telemetry Collector as an agent and Fluent Bit as an aggregator.

Installs Fluent Bit as a deployment (for an aggregator) and an Open Telemetry collector as a deamonset to collect logs from each node.

## Under development

Currently this configuration causes FLuent Bit to crash:

[https://github.com/fluent/fluent-bit/issues/6512#issuecomment-1367874130](https://github.com/fluent/fluent-bit/issues/6512#issuecomment-1367874130)


```bash
[2022/12/30 11:18:30] [ info] [sp] stream processor started
[2022/12/30 11:19:00] [engine] caught signal (SIGSEGV)
#0  0x55bc20e2bd9f      in  flb_sds_len() at include/fluent-bit/flb_sds.h:50
#1  0x55bc20e2fb57      in  cb_stdout_flush() at plugins/out_stdout/stdout.c:196
#2  0x55bc20aaf267      in  output_pre_cb_flush() at include/fluent-bit/flb_output.h:527
#3  0x55bc214eb266      in  co_init() at lib/monkey/deps/flb_libco/amd64.c:117
#4  0xffffffffffffffff  in  ???() at ???:0
```

We will update this configuration once this issue is resolved.

