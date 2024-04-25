# ClickHouse vs Elasticsearch for Real-time Analytics

These tests were performed on ClickHouse 24.4 and Elasticsearch 8.12.2.

## Goals

To provide a real-time analytics benchmark comparing ClickHouse and Elasticsearch when resources are comparable and all effort is made to optimize both.

## Schemas

### ClickHouse - Raw data storage

#### Tables
```
CREATE TABLE pypi_1b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
Engine = MergeTree
ORDER BY (project, timestamp);


CREATE TABLE pypi_10b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
Engine = MergeTree
ORDER BY (project, timestamp);


CREATE TABLE pypi_100b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
Engine = MergeTree
ORDER BY (project, timestamp);
```

### ClickHouse - Materialized Views

#### by-project-country_code Materialized View target tables
```
CREATE OR REPLACE TABLE pypi_1b_by_project_country_code
(
    `project` String,
    `country_code` LowCardinality(String),
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project, country_code);

CREATE OR REPLACE TABLE pypi_10b_by_project_country_code
(
    `project` String,
    `country_code` LowCardinality(String),
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project, country_code);

CREATE OR REPLACE TABLE pypi_100b_by_project_country_code
(
    `project` String,
    `country_code` LowCardinality(String),
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project, country_code);
```

#### by-project Materialized View target tables
```
CREATE OR REPLACE TABLE pypi_1b_by_project
(
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project);

CREATE OR REPLACE TABLE pypi_10b_by_project
(
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project); 

CREATE OR REPLACE TABLE pypi_100b_by_project
(
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project); 
```

#### by-project-country_code Materialized Views
```
CREATE MATERIALIZED VIEW pypi_1b_by_project_country_code_mv TO pypi_1b_by_project_country_code AS
SELECT
    project,
    country_code,
    count() AS count
FROM pypi_1b
GROUP BY project, country_code;

CREATE MATERIALIZED VIEW pypi_10b_by_project_country_code_mv TO pypi_10b_by_project_country_code AS
SELECT
    project,
    country_code,
    count() AS count
FROM pypi_10b
GROUP BY project, country_code;

CREATE MATERIALIZED VIEW pypi_100b_by_project_country_code_mv TO pypi_100b_by_project_country_code AS
SELECT
    project,
    country_code,
    count() AS count
FROM pypi_100b
GROUP BY project, country_code;
```

#### by-project-country_code Materialized Views
```
CREATE MATERIALIZED VIEW pypi_1b_by_project_mv TO pypi_1b_by_project AS
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project;    

CREATE MATERIALIZED VIEW pypi_10b_by_project_mv TO pypi_10b_by_project AS
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project; 

CREATE MATERIALIZED VIEW pypi_100b_by_project_mv TO pypi_100b_by_project AS
SELECT
    project,
    count() AS count
FROM pypi_100b
GROUP BY project; 
```


### Elasticsearch - Raw data storage

#### ILM Policy
```
PUT _ilm/policy/pypi-lifecycle-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "10gb",
            "max_primary_shard_docs" : 200000000
          }
        }
      }
    }
  }
}
```

#### Settings
```
PUT _component_template/pypi-settings
{
  "template": {
    "settings": {
      "index.lifecycle.name": "pypi-lifecycle-policy",
      "index.number_of_shards": 1,
      "index.number_of_replicas": 0
    }
  }
}
```

#### Mappings
```
PUT _component_template/mappings-pypi-with-source
{
  "template": {
    "mappings": {
      "_source": {
      "enabled": true
    },
      "properties": {
        "country_code": {
          "type": "keyword"
        },
        "project": {
          "type": "keyword"
        },
        "@timestamp": {
          "type": "date"
        },
        "url": {
          "type": "keyword"
        }
      }
    }
  }
}


PUT _component_template/mappings-pypi-without-source
{
  "template": {
    "mappings": {
      "_source": {
      "enabled": false
    },
      "properties": {
        "country_code": {
          "type": "keyword"
        },
        "project": {
          "type": "keyword"
        },
        "@timestamp": {
          "type": "date"
        },
        "url": {
          "type": "keyword"
        }
      }
    }
  }
}
```

#### Templates
```
PUT _index_template/pypi-s
{
  "index_patterns": ["pypi-1b-s", "pypi-10b-s", "pypi-100b-s"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-with-source", "pypi-settings" ],
  "priority": 500
}

PUT _index_template/pypi-ns
{
  "index_patterns": ["pypi-1b-ns", "pypi-10b-ns", "pypi-100b-ns"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-without-source", "pypi-settings" ],
  "priority": 500
}
```

#### Data streams
```
PUT _data_stream/pypi-1b-s
PUT _data_stream/pypi-1b-ns
PUT _data_stream/pypi-10b-s
PUT _data_stream/pypi-10b-ns
PUT _data_stream/pypi-100b-s
PUT _data_stream/pypi-100b-ns
```

### Elasticsearch - Transforms

#### Settings for transforms destination indexes
```
PUT _component_template/pypi-transforms-settings
{
  "template": {
    "settings": {
      "index.number_of_shards": 1,
      "index.number_of_replicas": 0
    }
  }
}
```

#### Mappings for by-project-country_code transforms destination indexes
```
PUT _component_template/mappings-pypi-by_project_country_code-without-source
{
  "template": {
    "mappings": {
      "_source": {
        "enabled": false
      },
      "properties": {
        "country_code": {
          "properties": {
            "terms": {
              "type": "flattened"
            }
          }
        },
        "country_codes": {
          "type": "keyword"
        },
        "projects": {
          "type": "keyword"
        }
      }
    }
  }
}
```
#### Mappings for by-project transforms destination indexes
```
PUT _component_template/mappings-pypi-by_project-without-source
{
  "template": {
    "mappings": {
      "_source": {
        "enabled": false
      },
      "properties": {
        "project": {
          "properties": {
            "terms": {
              "type": "flattened"
            }
          }
        },
        "projects": {
          "type": "keyword"
        }
      }
    }
  }
}
```

#### Templates for by-project-country_code transforms destination indexes
```
PUT _index_template/pypi_by_project_country_code
{
  "index_patterns": ["pypi_1b_by_project_country_code", "pypi_10b_by_project_country_code", "pypi_100b_by_project_country_code"],
  "composed_of": [ "mappings-pypi-by_project_country_code-without-source", "pypi-transforms-settings" ],
  "priority": 500
}
```

#### Templates for by-project transforms destination indexes
```
PUT _index_template/pypi_by_project
{
  "index_patterns": ["pypi_1b_by_project", "pypi_10b_by_project", "pypi_100b_by_project"],
  "composed_of": [ "mappings-pypi-by_project-without-source", "pypi-transforms-settings" ],
  "priority": 500
}
```

#### by-project-country_code transforms destination indexes
```
PUT pypi_1b_by_project_country_code
PUT pypi_10b_by_project_country_code
PUT pypi_100b_by_project_country_code
```

#### by-project transforms destination indexes
```
PUT pypi_1b_by_project
PUT pypi_10b_by_project
PUT pypi_100b_by_project
```

#### by-project-country_code transforms
```
PUT _transform/pypi_1b_by_project_country_code
{
  "source": {
    "index": [
      "pypi-1b-ns"
    ]
  },
  "pivot": {
     "group_by": {
    "projects": {
      "terms": {
        "field": "project"
      }
    },
    "country_codes": {
      "terms": {
        "field": "country_code"
      }
    }
  },
    "aggregations": {
      "country_code.terms": {
        "terms": {
          "field": "country_code"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_1b_by_project_country_code"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_1b_by_project_country_code/_start


PUT _transform/pypi_10b_by_project_country_code
{
  "source": {
    "index": [
      "pypi-10b-ns"
    ]
  },
  "pivot": {
     "group_by": {
    "projects": {
      "terms": {
        "field": "project"
      }
    },
    "country_codes": {
      "terms": {
        "field": "country_code"
      }
    }
  },
    "aggregations": {
      "country_code.terms": {
        "terms": {
          "field": "country_code"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_10b_by_project_country_code"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_10b_by_project_country_code/_start


PUT _transform/pypi_100b_by_project_country_code
{
  "source": {
    "index": [
      "pypi-100b-ns"
    ]
  },
  "pivot": {
     "group_by": {
    "projects": {
      "terms": {
        "field": "project"
      }
    },
    "country_codes": {
      "terms": {
        "field": "country_code"
      }
    }
  },
    "aggregations": {
      "country_code.terms": {
        "terms": {
          "field": "country_code"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_100b_by_project_country_code"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_100b_by_project_country_code/_start
```

#### by-project transforms
```
PUT _transform/pypi_1b_by_project
{
  "source": {
    "index": [
      "pypi-1b-ns"
    ]
  },
  "pivot": {
    "group_by": {
      "projects": {
         "terms": {
            "field": "project"
          }
       }
    },
    "aggregations": {
      "project.terms": {
        "terms": {
          "field": "project"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_1b_by_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_1b_by_project/_start


PUT _transform/pypi_10b_by_project
{
  "source": {
    "index": [
      "pypi-10b-ns"
    ]
  },
  "pivot": {
    "group_by": {
      "projects": {
         "terms": {
            "field": "project"
          }
       }
    },
    "aggregations": {
      "project.terms": {
        "terms": {
          "field": "project"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_10b_by_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_10b_by_project/_start


PUT _transform/pypi_100b_by_project
{
  "source": {
    "index": [
      "pypi-100b-ns"
    ]
  },
  "pivot": {
    "group_by": {
      "projects": {
         "terms": {
            "field": "project"
          }
       }
    },
    "aggregations": {
      "project.terms": {
        "terms": {
          "field": "project"
        }
      }
    }
  },
  "dest": {
    "index": "pypi_100b_by_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_100b_by_project/_start
```

## Queries on raw data sets

### Top 3 most popular projects

#### ClickHouse SQL
```
SELECT
    project,
    count() as count
FROM pypi_1b 
-- FROM pypi_10b
-- FROM pypi_100b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
```
# default sort size is by number of docs in decending order
#GET pypi-100b-ns/_search?request_cache=false
#GET pypi-10b-ns/_search?request_cache=false
GET pypi-1b-ns/_search?request_cache=false
{
  "size": 0,
  "aggregations": {
    "projects": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}
```

#### Elasticsearch ESQL
```
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}
```

### Top 3 countries for a specific project

#### ClickHouse SQL
```
SELECT
    country_code,
    count() as count
FROM pypi_1b_dt
-- FROM pypi_10b
-- FROM pypi_100b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
```
# default sort size is by number of docs in decending order
#GET pypi-100b-ns/_search?request_cache=false
#GET pypi-10b-ns/_search?request_cache=false
GET pypi-1b-ns/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "project": "boto3"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "country_code",
        "size": 3
      }
    }
  }
}
```

#### Elasticsearch ESQL
```
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | WHERE project == "boto3"
    | STATS count = COUNT() BY country_code 
    | SORT count DESC 
    | LIMIT 3
  """
}
```


## Queries on pre-aggregated data sets

### Top 3 most popular projects

#### ClickHouse SQL
```
SELECT
    project,
    sum(count) as count
FROM pypi_1b_by_project
-- FROM pypi_10b_by_project
-- FROM pypi_100b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
```
#GET pypi_100b_by_project/_search?request_cache=false
#GET pypi_10b_by_project/_search?request_cache=false
GET pypi_1b_by_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "match_all": {}
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['project.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}
```



### Top 3 countries for a specific project

#### ClickHouse SQL
```
SELECT
    country_code,
    sum(count) as count
FROM pypi_1b_by_project_country_code
-- FROM pypi_10b_by_project_country_code
-- FROM pypi_100b_by_project_country_code
WHERE project = 'boto3'
GROUP BY project, country_code
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
```
#GET pypi_100b_by_project_country_code/_search?request_cache=false
#GET pypi_10b_by_project_country_code/_search?request_cache=false
GET pypi_1b_by_project_country_code/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "projects": "boto3"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['country_code.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}
```

## Data loading

### Elasticsearch

#### Logstash configuration
```
input {
 stdin {}
}

filter {
    csv {
        separator => ","
        columns => ["timestamp","country_code","url","project"]
    }

    date {
      match => [ "timestamp", "yyyy-MM-dd HH:mm:ss.SSSSSS"]
      target => "@timestamp"
      remove_field => ["timestamp"]
    }

    mutate {
        remove_field => [ "%{@index}","%{@version}","%{@type}", "host", "log", "event", "message", "@version"]
    }
}

output {
  elasticsearch {
    hosts => [...]
    index => "pypi-1b-ns"
    action => "create"
    user => "elastic"
    password => "..."
    ssl => true
    cacert => "..."
  }
}
```
#### Load call
```
clickhouse local  -q "
SELECT
    timestamp,
    country_code,
    url,
    project
FROM s3(
    'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..61}-*.parquet',
    'Parquet',
    'timestamp DateTime64(6), country_code LowCardinality(String), url String, project String')
FORMAT CSV
SETTINGS
    input_format_null_as_default = 1,
    input_format_parquet_import_nested = 1;
" |  /home/ubuntu/logstash-8.13.2/bin/logstash -r -f "/home/ubuntu/logstash-8.13.2/config/pypi.conf"
```


### ClickHouse

#### Load SQL query
```
INSERT INTO pypi_1b
SELECT
    timestamp,
    country_code,
    url,
    project
FROM s3(
    'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..61}-*.parquet',
    'Parquet',
    'timestamp DateTime, country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String')
SETTINGS
    input_format_null_as_default = 1,
    input_format_parquet_import_nested = 1,
    max_insert_threads = 30;
```

## Storage sizes

### 1 billion row data set - raw data

#### Elasticsearch - LZ4 compression, with _source
```
#################################################
GET _data_stream/pypi-1b-s/_stats?human=true

{
  "_shards": {
    "total": 10,
    "successful": 10,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 10,
  "total_store_size": "137.1gb",
  "total_store_size_bytes": 147266949543,
  "data_streams": [
    {
      "data_stream": "pypi-1b-s",
      "backing_indices": 10,
      "store_size": "137.1gb",
      "store_size_bytes": 147266949543,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET pypi-1b-s/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 10,
    "successful": 10,
    "skipped": 0,
    "failed": 0
  }
}
```
#### Elasticsearch - LZ4 compression, without _source
```
#################################################
GET _data_stream/pypi-1b-ns/_stats?human=true

{
  "_shards": {
    "total": 6,
    "successful": 6,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 6,
  "total_store_size": "37.7gb",
  "total_store_size_bytes": 40502403385,
  "data_streams": [
    {
      "data_stream": "pypi-1b-ns",
      "backing_indices": 6,
      "store_size": "37.7gb",
      "store_size_bytes": 40502403385,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET pypi-1b-ns/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 6,
    "successful": 6,
    "skipped": 0,
    "failed": 0
  }
}
```
#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table───┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_1b │ 1.01 billion │ 126.63 GiB        │ 9.80 GiB        │ LZ4   │
   └─────────┴──────────────┴───────────────────┴─────────────────┴───────┘
```
#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b')
GROUP BY `table`
ORDER BY `table` ASC

┌─table───┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_1b │ 1.01 billion │ 126.63 GiB        │ 4.93 GiB        │ ZSTD(1) │
└─────────┴──────────────┴───────────────────┴─────────────────┴─────────┘
```

### 1 billion row data set -  pre-calculated `downloads per project` 

#### Elasticsearch - LZ4 compression, without _source
```
GET _cat/indices/pypi_1b_by_project?v&h=index,docs.count,pri.store.size&s=index

index              docs.count pri.store.size
pypi_1b_by_project     434776         48.4mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table──────────────┬─rows────────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_1b_by_project │ 434.78 thousand │ 9.17 MiB          │ 4.94 MiB        │ LZ4   │
   └────────────────────┴─────────────────┴───────────────────┴─────────────────┴───────┘
```
#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

┌─table──────────────┬─rows────────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_1b_by_project │ 434.78 thousand │ 9.17 MiB          │ 2.88 MiB        │ ZSTD(1) │
└────────────────────┴─────────────────┴───────────────────┴─────────────────┴─────────┘
```


### 1 billion row data set -  pre-calculated `downloads per project per country` 

#### Elasticsearch - LZ4 compression, without _source
```
GET _cat/indices/pypi_1b_by_project_country_code?v&h=index,docs.count,pri.store.size&s=index

index                           docs.count pri.store.size
pypi_1b_by_project_country_code    3523898        268.5mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project_country_code')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table───────────────────────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_1b_by_project_country_code │ 3.52 million │ 76.02 MiB         │ 15.18 MiB       │ LZ4   │
   └─────────────────────────────────┴──────────────┴───────────────────┴─────────────────┴───────┘
```
#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project_country_code')
GROUP BY `table`
ORDER BY `table` ASC

┌─table───────────────────────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_1b_by_project_country_code │ 3.52 million │ 76.24 MiB         │ 7.87 MiB        │ ZSTD(1) │
└─────────────────────────────────┴──────────────┴───────────────────┴─────────────────┴─────────┘
```




### 10 billion row data set - raw data

#### Elasticsearch - LZ4 compression, with _source
```
#################################################
GET _data_stream/pypi-10b-s/_stats?human=true

{
  "_shards": {
    "total": 82,
    "successful": 82,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 82,
  "total_store_size": "1.3tb",
  "total_store_size_bytes": 1470795109997,
  "data_streams": [
    {
      "data_stream": "pypi-10b-s",
      "backing_indices": 82,
      "store_size": "1.3tb",
      "store_size_bytes": 1470795109997,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET pypi-10b-s/_count

{
  "count": 10012252471,
  "_shards": {
    "total": 82,
    "successful": 82,
    "skipped": 0,
    "failed": 0
  }
}
```
#### Elasticsearch - LZ4 compression, without _source
```
#################################################
GET _data_stream/pypi-10b-ns/_stats?human=true

{
  "_shards": {
    "total": 53,
    "successful": 53,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 53,
  "total_store_size": "522.2gb",
  "total_store_size_bytes": 560727639492,
  "data_streams": [
    {
      "data_stream": "pypi-10b-ns",
      "backing_indices": 53,
      "store_size": "522.2gb",
      "store_size_bytes": 560727639492,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET pypi-10b-ns/_count

{
  "count": 10012252471,
  "_shards": {
    "total": 53,
    "successful": 53,
    "skipped": 0,
    "failed": 0
  }
}
```
#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table────┬─rows──────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_10b │ 10.01 billion │ 1.22 TiB          │ 77.27 GiB       │ LZ4   │
   └──────────┴───────────────┴───────────────────┴─────────────────┴───────┘
```

#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b')
GROUP BY `table`
ORDER BY `table` ASC

┌─table────┬─rows──────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_10b │ 10.01 billion │ 1.22 TiB          │ 35.08 GiB       │ ZSTD(1) │
└──────────┴───────────────┴───────────────────┴─────────────────┴─────────┘
```

### 10 billion row data set -  pre-calculated `downloads per project` 

#### Elasticsearch - LZ4 compression, without _source
```
GET _cat/indices/pypi_10b_by_project?v&h=index,docs.count,pri.store.size&s=index

index              docs.count pri.store.size
pypi_10b_by_project     465978         45.6mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table───────────────┬─rows────────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_10b_by_project │ 465.98 thousand │ 9.85 MiB          │ 5.39 MiB        │ LZ4   │
   └─────────────────────┴─────────────────┴───────────────────┴─────────────────┴───────┘
```
#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

┌─table───────────────┬─rows────────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_10b_by_project │ 465.98 thousand │ 9.85 MiB          │ 3.32 MiB        │ ZSTD(1) │
└─────────────────────┴─────────────────┴───────────────────┴─────────────────┴─────────┘
```


### 10 billion row data set -  pre-calculated `downloads per project per country` 

#### Elasticsearch - LZ4 compression, without _source
```
GET _cat/indices/pypi_1b_by_project_country_code?v&h=index,docs.count,pri.store.size&s=index

TODO
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_project_country_code')
GROUP BY `table`
ORDER BY `table` ASC

   ┌─table────────────────────────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec─┐
1. │ pypi_10b_by_project_country_code │ 8.79 million │ 190.99 MiB        │ 32.81 MiB       │ LZ4   │
   └──────────────────────────────────┴──────────────┴───────────────────┴─────────────────┴───────┘
```
#### ClickHouse Cloud - ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed,
    any(default_compression_codec) AS codec
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_project_country_code')
GROUP BY `table`
ORDER BY `table` ASC

┌─table────────────────────────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┬─codec───┐
│ pypi_10b_by_project_country_code │ 8.79 million │ 191.55 MiB        │ 15.09 MiB       │ ZSTD(1) │
└──────────────────────────────────┴──────────────┴───────────────────┴─────────────────┴─────────┘
```











## Query runtimes

### 1 billion row data set - raw data - downloads per project

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 


```
GET pypi-1b-ns/_search?request_cache=false
{
  "size": 0,
  "aggregations": {
	"projects": {
	  "terms": {
		"field": "project",
		"size": 3
	  }
	 }
  }
}

TODO
```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

TODO
```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 64587b99-921a-4bb6-a9f9-57f5f664c449

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.768 sec. Processed 1.01 billion rows, 19.08 GB (1.32 billion rows/s., 24.84 GB/s.)
Peak memory usage: 265.46 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 41ab1297-69f4-4507-8e0c-e9a98b0b0aa1

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.794 sec. Processed 1.01 billion rows, 19.08 GB (1.27 billion rows/s., 24.02 GB/s.)
Peak memory usage: 265.23 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: c0a6947a-ad7f-4323-8201-403330edff39

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.765 sec. Processed 1.01 billion rows, 19.08 GB (1.32 billion rows/s., 24.94 GB/s.)
Peak memory usage: 265.24 MiB.
```

#### ClickHouse Cloud - 1 node with 4 CPU cores per node - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 4, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 32af5808-24d6-4822-a36c-cddd05080f65

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 4.672 sec. Processed 1.01 billion rows, 19.08 GB (216.72 million rows/s., 4.08 GB/s.)
Peak memory usage: 257.99 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 30, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 3314f248-55f8-41b8-8a53-c9ce8f6a7fcf

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 4.657 sec. Processed 1.01 billion rows, 19.08 GB (217.46 million rows/s., 4.10 GB/s.)
Peak memory usage: 257.99 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 30, enable_filesystem_cache = 0, use_query_cache = 0

Query id: f4797fc0-52c1-4f33-9f79-d061e7a08cbb

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 4.639 sec. Processed 1.01 billion rows, 19.08 GB (218.30 million rows/s., 4.11 GB/s.)
Peak memory usage: 257.99 MiB.

```

### 1 billion row data set - raw data - downloads per country for a specific project

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi-1b-ns/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "project": "boto3"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "country_code",
        "size": 3
      }
    }
  }
}


TODO
```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | WHERE project == "boto3"
    | STATS count = COUNT() BY country_code 
    | SORT count DESC 
    | LIMIT 3
  """
}


TODO
```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_1b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 9e71fa34-17fd-4561-b61a-d003bacbdeae

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.033 sec. Processed 28.21 million rows, 423.33 MB (853.12 million rows/s., 12.80 GB/s.)
Peak memory usage: 1.77 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_1b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 3a9d2e33-4f46-42d2-99a1-b7681640205e

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.035 sec. Processed 28.21 million rows, 423.33 MB (815.28 million rows/s., 12.23 GB/s.)
Peak memory usage: 1.23 MiB.


------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_1b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 081d1207-19f3-4014-b8b2-da49b7f52621

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.034 sec. Processed 28.21 million rows, 423.33 MB (827.62 million rows/s., 12.42 GB/s.)
Peak memory usage: 1.75 MiB.

```


### 1 billion row data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi_1b_by_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "match_all": {}
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['project.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}

TODO
```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 9102dbd5-42cd-40e2-997a-e552a071a889

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.030 sec. Processed 434.78 thousand rows, 13.10 MB (14.65 million rows/s., 441.30 MB/s.)
Peak memory usage: 72.06 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: fdfd4f83-485c-4f43-b1a0-e388ddeae40e

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.028 sec. Processed 434.78 thousand rows, 13.10 MB (15.29 million rows/s., 460.50 MB/s.)
Peak memory usage: 72.06 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: b9556961-4a75-4a3c-8daf-bf06ad35e4e5

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.025 sec. Processed 434.78 thousand rows, 13.10 MB (17.69 million rows/s., 532.90 MB/s.)
Peak memory usage: 72.06 MiB.
```

### 1 billion row data set - pre-calculated `downloads per project per country` 

#### Elasticsearch - Query DSL
```
GET pypi_1b_by_project_country_code/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "projects": "boto3"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['country_code.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}


TODO
```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    sum(count) AS count
FROM pypi_1b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 676c8507-daff-4309-a76d-420abc9b9c16

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.004 sec. Processed 8.19 thousand rows, 236.83 KB (1.92 million rows/s., 55.63 MB/s.)
Peak memory usage: 97.08 KiB.

------------------------------------------------------------------------------------------------------------------------

SELECT
    country_code,
    sum(count) AS count
FROM pypi_1b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: e25feef9-8bb0-4aa5-ba58-37e88a38774f

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.004 sec. Processed 8.19 thousand rows, 236.83 KB (1.95 million rows/s., 56.50 MB/s.)
Peak memory usage: 97.11 KiB.
------------------------------------------------------------------------------------------------------------------------

SELECT
    country_code,
    sum(count) AS count
FROM pypi_1b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 9360976e-17df-490f-9a08-7ff7ce2c9b11

   ┌─country_code─┬────count─┐
1. │ US           │ 20605160 │
2. │ IE           │  1738337 │
3. │ SG           │  1608552 │
   └──────────────┴──────────┘

3 rows in set. Elapsed: 0.004 sec. Processed 8.19 thousand rows, 236.83 KB (2.08 million rows/s., 60.14 MB/s.)
Peak memory usage: 99.61 KiB.
```




### 10 billion row data set - raw data - downloads per project

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi-10b-ns/_search?request_cache=false
{
  "size": 0,
  "aggregations": {
	"projects": {
	  "terms": {
		"field": "project",
		"size": 3
	  }
	 }
  }
}


TODO
```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}


TODO
```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: ef12d292-5e34-478f-954b-62421b20b1e6

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 7.374 sec. Processed 10.01 billion rows, 188.61 GB (1.36 billion rows/s., 25.58 GB/s.)
Peak memory usage: 272.34 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: b8a35e6d-b868-46e0-8a04-d4e41abf449b

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 7.439 sec. Processed 10.01 billion rows, 188.61 GB (1.35 billion rows/s., 25.35 GB/s.)
Peak memory usage: 268.36 MiB.

------------------------------------------------------------------------------------------------------------------------
    project,
    count() AS count
FROM pypi_10b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 6e595a46-5660-4678-807d-b06d192ceb38

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 7.366 sec. Processed 10.01 billion rows, 188.61 GB (1.36 billion rows/s., 25.60 GB/s.)
Peak memory usage: 269.40 MiB.
```

### 10 billion row data set - raw data - downloads per country for a specific project

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi-10b-ns/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "project": "boto3"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "country_code",
        "size": 3
      }
    }
  }
}


TODO
```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns
    | WHERE project == "boto3"
    | STATS count = COUNT() BY country_code 
    | SORT count DESC 
    | LIMIT 3
  """
}


TODO
```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_10b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: abbe7fc9-5aca-44f6-8bbc-45dcb9ee8088

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.213 sec. Processed 278.88 million rows, 4.18 GB (1.31 billion rows/s., 19.67 GB/s.)
Peak memory usage: 3.05 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_10b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 6b3bc566-34b8-46ba-bee1-a30eda80396a

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.210 sec. Processed 278.88 million rows, 4.18 GB (1.33 billion rows/s., 19.94 GB/s.)
Peak memory usage: 2.00 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    count() AS count
FROM pypi_10b
WHERE project = 'boto3'
GROUP BY country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: a85f6f72-bfc2-43ce-9494-448d593700d7

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.205 sec. Processed 278.88 million rows, 4.18 GB (1.36 billion rows/s., 20.40 GB/s.)
Peak memory usage: 2.78 MiB.
```


### 10 billion row data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi_10b_by_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "match_all": {}
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['project.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}

TODO
```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: ac6af0a9-a253-49f0-8954-080fe99d81d8

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.027 sec. Processed 465.98 thousand rows, 14.06 MB (17.26 million rows/s., 520.81 MB/s.)
Peak memory usage: 64.05 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: cac3dceb-18d8-4b07-8848-e03f1c95aaea

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.028 sec. Processed 465.98 thousand rows, 14.06 MB (16.58 million rows/s., 500.17 MB/s.)
Peak memory usage: 64.05 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 96975613-5f4e-47e1-a846-01dd45ae9105

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.025 sec. Processed 465.98 thousand rows, 14.06 MB (18.45 million rows/s., 556.57 MB/s.)
Peak memory usage: 64.05 MiB.
```

### 10 billion row data set -  pre-calculated `downloads per project per country` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
GET pypi_10b_by_project_country_code/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "projects": "boto3"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
        String s = doc['country_code.terms'].value;
          int idvalue = Integer.parseInt(s);
          return idvalue;
        """
      }
    }
  }
}


TODO
```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    sum(count) AS count
FROM pypi_10b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 67968b60-50f2-46a9-983a-6c2097924cf3

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.004 sec. Processed 8.19 thousand rows, 300.10 KB (1.87 million rows/s., 68.46 MB/s.)
Peak memory usage: 101.06 KiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    sum(count) AS count
FROM pypi_10b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 5e0ab147-4ebc-4ce8-a821-e0d7e1f1ec88

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.005 sec. Processed 8.19 thousand rows, 300.10 KB (1.74 million rows/s., 63.66 MB/s.)
Peak memory usage: 101.09 KiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    country_code,
    sum(count) AS count
FROM pypi_10b_by_project_country_code
WHERE project = 'boto3'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: f0d2c5a6-55ac-4c57-b81b-254cc317967f

   ┌─country_code─┬─────count─┐
1. │ US           │ 203759297 │
2. │ IE           │  17175943 │
3. │ SG           │  15901152 │
   └──────────────┴───────────┘

3 rows in set. Elapsed: 0.004 sec. Processed 8.19 thousand rows, 300.10 KB (1.85 million rows/s., 67.69 MB/s.)
Peak memory usage: 101.06 KiB.
```






## Misc

### Process for dropping filesystem cache for Elasticsearch

- stopping the Elasticsearch node
- running a Linux command for dropping the os-level filesystem cache:
`echo 3 | sudo tee /proc/sys/vm/drop_caches` 
- restarting the Elasticsearch node

### Timings for backfilling pre-aggregations in Elasticsearch using a batch transform

### Process for backfilling pre-aggregations in ClickHouse

#### Variant 1 - directly inserting into the target table by using the materialized view's transformation query
```
CREATE OR REPLACE TABLE pypi_10b_by_project_country_code_backfilled
(
    `project` String,
    `country_code` LowCardinality(String),
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project, country_code);
```

```
INSERT INTO pypi_10b_by_project_country_code_backfilled
SELECT
    project,
    country_code,
    count() AS count
FROM pypi_10b
GROUP BY project, country_code
SETTINGS
    max_threads = 32,
    max_insert_threads = 32;

0 rows in set. Elapsed: 19.901 sec. Processed 10.01 billion rows, 198.63 GB (503.10 million rows/s., 9.98 GB/s.)
Peak memory usage: 1.95 GiB.
```

#### Variant 2 - table to table copy into a Null table engine table with a connected materialized view

Depending on the cardinality of the raw data set, variant 1 is a memory-intensive approach. Alternatively, users can utilize an approach requiring minimal memory by 

1. Creating a temporary table with a [Null table engine](https://clickhouse.com/docs/en/engines/table-engines/special/null) 
2. Connecting a copy of the normally used materialized view to that temporary table
3. Using an INSERT INTO SELECT query, copying all data from the raw data set into that temporary table
4. Dropping the temporary table

With that approach, rows from the raw data set are copied block-wise into the temporary table (which doesn’t store any of these rows), and for each block of rows, a [partial state](https://github.com/ClickHouse/examples/blob/main/ClickHouse_vs_ElasticSearch/DataAnalytics/internals/Continuous_data_transformation/README.md#clickhouse) is calculated and written to the target table, where these states are [incrementally merged](https://github.com/ClickHouse/examples/blob/main/ClickHouse_vs_ElasticSearch/DataAnalytics/internals/Continuous_data_transformation/README.md#clickhouse) in the background.


```
CREATE OR REPLACE TABLE pypi_10b_null
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
ENGINE = Null;
```

```
CREATE OR REPLACE TABLE pypi_10b_by_project_country_code_backfilled
(
    `project` String,
    `country_code` LowCardinality(String),
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project, country_code);
```

```
CREATE MATERIALIZED VIEW pypi_10b_by_project_country_code_mv_backfilled TO pypi_10b_by_project_country_code_backfilled AS
SELECT
    project,
    country_code,
    count() AS count
FROM pypi_10b_null
GROUP BY project, country_code;
```
```
INSERT INTO pypi_10b_null
SELECT * FROM pypi_10b
SETTINGS
    max_threads = 30,
    max_insert_threads = 30;
```


