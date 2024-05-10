# ClickHouse vs Elasticsearch for Real-time Analytics

These tests were performed on ClickHouse 24.4 and Elasticsearch 8.12.2.

## Goals

To provide a real-time analytics benchmark comparing ClickHouse and Elasticsearch when resources are comparable and all effort is made to optimize both.

## Schemas

### ClickHouse - Raw data storage

#### Tables
```
CREATE OR REPLACE TABLE pypi_1b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
ORDER BY (country_code, project, url, timestamp);
```
```
CREATE OR REPLACE TABLE pypi_1b_zstd
(
    `timestamp` DateTime CODEC(ZSTD),
    `country_code` LowCardinality(String) CODEC(ZSTD),
    `url` String CODEC(ZSTD),
    `project` String CODEC(ZSTD)
)
ORDER BY (country_code, project, url, timestamp);
```
```
CREATE OR REPLACE TABLE pypi_10b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
ORDER BY (country_code, project, url, timestamp);
```
```
CREATE OR REPLACE TABLE pypi_10b_zstd
(
    `timestamp` DateTime CODEC(ZSTD),
    `country_code` LowCardinality(String) CODEC(ZSTD),
    `url` String CODEC(ZSTD),
    `project` String CODEC(ZSTD)
)
ORDER BY (country_code, project, url, timestamp);
```
```
CREATE OR REPLACE TABLE pypi_100b
(
    `timestamp` DateTime,
    `country_code` LowCardinality(String),
    `url` String,
    `project` String
)
ORDER BY (country_code, project, url, timestamp);
```
```
CREATE OR REPLACE TABLE pypi_100b_zstd
(
    `timestamp` DateTime CODEC(ZSTD),
    `country_code` LowCardinality(String) CODEC(ZSTD),
    `url` String CODEC(ZSTD),
    `project` String CODEC(ZSTD)
)
ORDER BY (country_code, project, url, timestamp);
```

### ClickHouse - Materialized Views

#### by-country_code-project Materialized View target tables
```
CREATE OR REPLACE TABLE pypi_1b_by_country_code_project
(
    `country_code` LowCardinality(String),
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (country_code, project);
```
```
CREATE OR REPLACE TABLE pypi_10b_by_country_code_project
(
    `country_code` LowCardinality(String),
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (country_code, project);
```
```
CREATE OR REPLACE TABLE pypi_100b_by_country_code_project
(
    `country_code` LowCardinality(String),
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (country_code, project);
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
```
```
CREATE OR REPLACE TABLE pypi_10b_by_project
(
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project); 
```
```
CREATE OR REPLACE TABLE pypi_100b_by_project
(
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (project); 
```

#### by-country_code_project Materialized Views
```
CREATE MATERIALIZED VIEW pypi_1b_by_country_code_project_mv TO pypi_1b_by_country_code_project AS
SELECT
    country_code,
    project,
    count() AS count
FROM pypi_1b
GROUP BY country_code, project;
```
```
CREATE MATERIALIZED VIEW pypi_10b_by_country_code_project_mv TO pypi_10b_by_country_code_project AS
SELECT
    country_code,
    project,
    count() AS count
FROM pypi_10b
GROUP BY country_code, project;
```
```
CREATE MATERIALIZED VIEW pypi_100b_by_country_code_project_mv TO pypi_100b_by_country_code_project AS
SELECT
    country_code,
    project,
    count() AS count
FROM pypi_100b
GROUP BY country_code, project;
```

#### by-project Materialized Views
```
CREATE MATERIALIZED VIEW pypi_1b_by_project_mv TO pypi_1b_by_project AS
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project;    
```
```
CREATE MATERIALIZED VIEW pypi_10b_by_project_mv TO pypi_10b_by_project AS
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project; 
```
```
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
          },
           "forcemerge" : {
            "max_num_segments": 1
          }
        }
      }
    }
  }
}
```

#### Settings
##### No index sorting, `LZ4` codec
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
##### Index sorting, `LZ4` codec
```
PUT _component_template/pypi-settings-index_sorting
{
  "template": {
    "settings": {
      "index.lifecycle.name": "pypi-lifecycle-policy",
      "index.number_of_shards": 1,
      "index.number_of_replicas": 0,
      "index.sort.field": ["country_code", "project", "url", "@timestamp"],
      "index.sort.order": ["asc", "asc", "asc", "asc"]
    }
  }
}
```
##### Index sorting, `DEFLATE` codec
```
PUT _component_template/pypi-settings-index_sorting-best_compression
{
  "template": {
    "settings": {
      "index.lifecycle.name": "pypi-lifecycle-policy",
      "index.number_of_shards": 1,
      "index.number_of_replicas": 0,
      "index.sort.field": ["country_code", "project", "url", "@timestamp"],
      "index.sort.order": ["asc", "asc", "asc", "asc"],
      "index.codec": "best_compression"
    }
  }
}
```

#### Mappings
##### With `_source`
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
```
##### Without `_source`
```
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

##### With `_source`, No index sorting, `LZ4` codec
```
PUT _index_template/pypi-s
{
  "index_patterns": ["pypi-1b-s", "pypi-10b-s", "pypi-100b-s"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-with-source", "pypi-settings" ],
  "priority": 500
}
```
##### Without `_source`, No index sorting, `LZ4` codec
```
PUT _index_template/pypi-ns
{
  "index_patterns": ["pypi-1b-ns", "pypi-10b-ns", "pypi-100b-ns"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-without-source", "pypi-settings" ],
  "priority": 500
}
```
##### With `_source`, Index sorting, `LZ4` codec
```
PUT _index_template/pypi-s-index_sorting
{
  "index_patterns": ["pypi-1b-s-index_sorting", "pypi-10b-s-index_sorting", "pypi-100b-s-index_sorting"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-with-source", "pypi-settings-index_sorting" ],
  "priority": 500
}
```
##### With `_source`, Index sorting, `DEFLATE` codec
```
PUT _index_template/pypi-s-index_sorting-best_compression
{
  "index_patterns": ["pypi-1b-s-index_sorting-best_compression", "pypi-10b-s-index_sorting-best_compression", "pypi-100b-s-index_sorting-best_compression"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-with-source", "pypi-settings-index_sorting-best_compression" ],
  "priority": 500
}
```
##### Without `_source`, Index sorting, `LZ4` codec
```
PUT _index_template/pypi-ns-index_sorting
{
  "index_patterns": ["pypi-1b-ns-index_sorting", "pypi-10b-ns-index_sorting", "pypi-100b-ns-index_sorting"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-without-source", "pypi-settings-index_sorting" ],
  "priority": 500
}
```
##### Without `_source`, Index sorting, `DEFLATE` codec
```
PUT _index_template/pypi-ns-index_sorting-best_compression
{
  "index_patterns": ["pypi-1b-ns-index_sorting-best_compression", "pypi-10b-ns-index_sorting-best_compression", "pypi-100b-ns-index_sorting-best_compression"],
  "data_stream": { },
  "composed_of": [ "mappings-pypi-without-source", "pypi-settings-index_sorting-best_compression" ],
  "priority": 500
}
```

#### Data streams
##### With `_source`, No index sorting, `LZ4` codec
```
PUT _data_stream/pypi-1b-s
PUT _data_stream/pypi-10b-s
PUT _data_stream/pypi-100b-s
```
##### Without `_source`, No index sorting, `LZ4` codec
```
PUT _data_stream/pypi-1b-ns
PUT _data_stream/pypi-10b-ns
PUT _data_stream/pypi-100b-ns
```
##### With `_source`, Index sorting, `LZ4` codec
```
PUT _data_stream/pypi-1b-s-index_sorting
PUT _data_stream/pypi-10b-s-index_sorting
PUT _data_stream/pypi-100b-s-index_sorting
```
##### With `_source`, Index sorting, `DEFLATE` codec
```
PUT _data_stream/pypi-1b-s-index_sorting-best_compression
PUT _data_stream/pypi-10b-s-index_sorting-best_compression
PUT _data_stream/pypi-100b-s-index_sorting-best_compression
```
##### Without `_source`, Index sorting, `LZ4` codec
```
PUT _data_stream/pypi-1b-ns-index_sorting
PUT _data_stream/pypi-10b-ns-index_sorting
PUT _data_stream/pypi-100b-ns-index_sorting
```
##### Without `_source`, Index sorting, `DEFLATE` codec
```
PUT _data_stream/pypi-1b-ns-index_sorting-best_compression
PUT _data_stream/pypi-10b-ns-index_sorting-best_compression
PUT _data_stream/pypi-100b-ns-index_sorting-best_compression
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

#### Mappings for by-country_code-project transforms destination indexes
```
PUT _component_template/mappings-pypi-by_country_code_project-without-source
{
  "template": {
    "mappings": {
      "_source": {
        "enabled": false
      },
      "properties": {
        "country_code_group": {
          "type": "keyword"
        },
        "project_group": {
          "type": "keyword"
        },
        "project": {
          "properties": {
            "terms": {
              "type": "flattened"
            }
          }
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
        "project_group": {
          "type": "keyword"
        },
        "project": {
          "properties": {
            "terms": {
              "type": "flattened"
            }
          }
        }
      }
    }
  }
}
```

#### Templates for by-country_code-project-transforms destination indexes
```
PUT _index_template/pypi_by_country_code_project
{
  "index_patterns": ["pypi_1b_by_country_code_project", "pypi_10b_by_country_code_project", "pypi_100b_by_country_code_project"],
  "composed_of": [ "mappings-pypi-by_country_code_project-without-source", "pypi-transforms-settings" ],
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

#### by-country_code-project transforms destination indexes
```
PUT pypi_1b_by_country_code_project
PUT pypi_10b_by_country_code_project
PUT pypi_100b_by_country_code_project
```

#### by-project transforms destination indexes
```
PUT pypi_1b_by_project
PUT pypi_10b_by_project
PUT pypi_100b_by_project
```

#### by-country_code-project transforms
```
PUT _transform/pypi_1b_by_country_code_project
{
  "source": {
    "index": [
      "pypi-1b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
    "country_code_group": {
      "terms": {
        "field": "country_code"
      }
    },
    "project_group": {
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
    "index": "pypi_1b_by_country_code_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_1b_by_country_code_project/_start

```
```
PUT _transform/pypi_10b_by_country_code_project
{
  "source": {
    "index": [
      "pypi-10b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
    "country_code_group": {
      "terms": {
        "field": "country_code"
      }
    },
    "project_group": {
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
    "index": "pypi_10b_by_country_code_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_10b_by_country_code_project/_start

```
```
PUT _transform/pypi_100b_by_country_code_project
{
  "source": {
    "index": [
      "pypi-100b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
    "country_code_group": {
      "terms": {
        "field": "country_code"
      }
    },
    "project_group": {
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
    "index": "pypi_100b_by_country_code_project"
  },
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  }
}
POST _transform/pypi_100b_by_country_code_project/_start

```

#### by-project transforms
```
PUT _transform/pypi_1b_by_project
{
  "source": {
    "index": [
      "pypi-1b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
      "project_group": {
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
```
```
PUT _transform/pypi_10b_by_project
{
  "source": {
    "index": [
      "pypi-10b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
      "project_group": {
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
```
```
PUT _transform/pypi_100b_by_project
{
  "source": {
    "index": [
      "pypi-100b-ns-index_sorting"
    ]
  },
  "pivot": {
    "group_by": {
      "project_group": {
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
GET pypi-1b-ns-index_sorting/_search?request_cache=false
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
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}
```

### Top 3 projects for a specific country

#### ClickHouse SQL
```
SELECT
    project,
    count() as count
FROM pypi_1b
WHERE country_code = 'NL'
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
GET pypi-1b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
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
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
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
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
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
  },
  "docvalue_fields": ["project_group"]
}
```



### Top 3 projects for a specific country

#### ClickHouse SQL
```
SELECT
    project,
    sum(count) as count
FROM pypi_1b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY project, country_code
ORDER BY count DESC
LIMIT 3
SETTINGS
    enable_filesystem_cache=0,
    use_query_cache=0;
```

#### Elasticsearch query DSL
```
GET pypi_1b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
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
  },
  "docvalue_fields": ["project_group"]
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
    index => "pypi-1b-ns-index_sorting"
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

##### 1 billion row dataset
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
    max_insert_threads = 32;
```

```
INSERT INTO pypi_1b_zstd
SELECT * FROM pypi_1b
SETTINGS
    max_threads=32,
    max_insert_threads=32;
```

##### 10 billion row dataset

```
INSERT INTO pypi_10b
SELECT
    timestamp,
    country_code,
    url,
    project
FROM s3(
    'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..612}-*.parquet',
    'Parquet',
    'timestamp DateTime, country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String')
SETTINGS
    input_format_null_as_default = 1,
    input_format_parquet_import_nested = 1,
    max_insert_threads = 32;
```

```
INSERT INTO pypi_10b_zstd
SELECT * FROM pypi_10b
SETTINGS
    max_threads=10,
    max_insert_threads=10;
```

##### 100 billion row dataset

```
INSERT INTO pypi_100b
SELECT
    timestamp,
    country_code,
    url,
    project
FROM s3(
    'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/*/*/*.parquet',
    'Parquet',
    'timestamp DateTime, country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String')
SETTINGS
    input_format_null_as_default = 1,
    input_format_parquet_import_nested = 1,
    max_insert_threads = 32;
```

```
INSERT INTO pypi_100b_zstd
SELECT * FROM pypi_100b
SETTINGS
    max_threads=10,
    max_insert_threads=10;
```


## Storage sizes

### 1 billion raw data set - raw data

#### Elasticsearch

##### With `_source`, No index sorting, `LZ4` codec
```
#################################################
GET _data_stream/pypi-1b-s/_stats?human=true

{
  "_shards": {
    "total": 12,
    "successful": 12,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 12,
  "total_store_size": "135.6gb",
  "total_store_size_bytes": 145666640935,
  "data_streams": [
    {
      "data_stream": "pypi-1b-s",
      "backing_indices": 12,
      "store_size": "135.6gb",
      "store_size_bytes": 145666640935,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-s-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                           shard segment docs.count   size
.ds-pypi-1b-s-2024.04.25-000001 0     _131      79501500 10.6gb
.ds-pypi-1b-s-2024.04.25-000002 0     _1ng      83556500 11.2gb
.ds-pypi-1b-s-2024.04.25-000003 0     _175      88098500 11.8gb
.ds-pypi-1b-s-2024.04.25-000004 0     _183      86458500 11.5gb
.ds-pypi-1b-s-2024.04.25-000005 0     _1au      91207000 12.2gb
.ds-pypi-1b-s-2024.04.25-000006 0     _1ab      90580500   12gb
.ds-pypi-1b-s-2024.04.25-000007 0     _1i1      89393500   12gb
.ds-pypi-1b-s-2024.04.25-000008 0     _1jb      92265000 12.3gb
.ds-pypi-1b-s-2024.04.25-000009 0     _1db      85419500 11.4gb
.ds-pypi-1b-s-2024.04.25-000010 0     _17g      85570500 11.4gb
.ds-pypi-1b-s-2024.04.25-000011 0     _180      97376000   13gb
.ds-pypi-1b-s-2024.04.25-000012 0     _o5       43211142  5.7gb

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
##### Without `_source`, No index sorting, `LZ4` codec
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
  "total_store_size_bytes": 40502403386,
  "data_streams": [
    {
      "data_stream": "pypi-1b-ns",
      "backing_indices": 6,
      "store_size": "37.7gb",
      "store_size_bytes": 40502403386,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-ns-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                            shard segment docs.count  size
.ds-pypi-1b-ns-2024.04.22-000001 0     _2py     184986000 6.8gb
.ds-pypi-1b-ns-2024.04.22-000002 0     _27p     199505000 7.4gb
.ds-pypi-1b-ns-2024.04.22-000003 0     _2t1     192391000 7.1gb
.ds-pypi-1b-ns-2024.04.22-000004 0     _2if     194322500 7.2gb
.ds-pypi-1b-ns-2024.04.22-000005 0     _2fc     195489500 7.2gb
.ds-pypi-1b-ns-2024.04.22-000006 0     _m6       45944142 1.7gb


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
##### With `_source`, No index sorting, `DELATE` codec
```
#################################################
GET _data_stream/pypi-1b-s-best_compression/_stats?human=true

{
  "_shards": {
    "total": 9,
    "successful": 9,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 9,
  "total_store_size": "91.5gb",
  "total_store_size_bytes": 98335202156,
  "data_streams": [
    {
      "data_stream": "pypi-1b-s-best_compression",
      "backing_indices": 9,
      "store_size": "91.5gb",
      "store_size_bytes": 98335202156,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-s-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                            shard segment docs.count   size
.ds-pypi-1b-s-best_compression-2024.04.25-000001 0     _1am     109129000  9.8gb
.ds-pypi-1b-s-best_compression-2024.04.25-000002 0     _193     114992500 10.4gb
.ds-pypi-1b-s-best_compression-2024.04.25-000003 0     _1ay     113481500 10.2gb
.ds-pypi-1b-s-best_compression-2024.04.25-000004 0     _1d2     119589500 10.8gb
.ds-pypi-1b-s-best_compression-2024.04.25-000005 0     _1cr     120156000 10.8gb
.ds-pypi-1b-s-best_compression-2024.04.25-000006 0     _17b     123711000 11.2gb
.ds-pypi-1b-s-best_compression-2024.04.25-000007 0     _1af     110272000  9.9gb
.ds-pypi-1b-s-best_compression-2024.04.25-000008 0     _189     126567500 11.4gb
.ds-pypi-1b-s-best_compression-2024.04.25-000009 0     _v9       74739142  6.7gb

#################################################
GET pypi-1b-s-best_compression/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 9,
    "successful": 9,
    "skipped": 0,
    "failed": 0
  }
}
```
##### Without `_source`, No index sorting, `DEFLATE` codec
```
#################################################
GET _data_stream/pypi-1b-ns-best_compression/_stats?human=true

{
  "_shards": {
    "total": 5,
    "successful": 5,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 5,
  "total_store_size": "35.4gb",
  "total_store_size_bytes": 38114843146,
  "data_streams": [
    {
      "data_stream": "pypi-1b-ns-best_compression",
      "backing_indices": 5,
      "store_size": "35.4gb",
      "store_size_bytes": 38114843146,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-ns-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                             shard segment docs.count  size
.ds-pypi-1b-ns-best_compression-2024.04.25-000001 0     _2je     224116000 7.8gb
.ds-pypi-1b-ns-best_compression-2024.04.25-000002 0     _25f     204698000 7.1gb
.ds-pypi-1b-ns-best_compression-2024.04.25-000003 0     _272     209775000 7.3gb
.ds-pypi-1b-ns-best_compression-2024.04.25-000004 0     _2ao     201817500   7gb
.ds-pypi-1b-ns-best_compression-2024.04.25-000005 0     _1ok     172231642   6gb


#################################################
GET pypi-1b-ns-best_compression/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  }
}
```
##### With `_source`, Index sorting, `LZ4` codec
```
#################################################
GET _data_stream/pypi-1b-s-index_sorting/_stats?human=true

{
  "_shards": {
    "total": 6,
    "successful": 6,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 6,
  "total_store_size": "51.3gb",
  "total_store_size_bytes": 55090334138,
  "data_streams": [
    {
      "data_stream": "pypi-1b-s-index_sorting",
      "backing_indices": 6,
      "store_size": "51.3gb",
      "store_size_bytes": 55090334138,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-s-index_sorting-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                         shard segment docs.count  size
.ds-pypi-1b-s-index_sorting-2024.04.25-000001 0     _3fp     175407500 8.8gb
.ds-pypi-1b-s-index_sorting-2024.04.25-000002 0     _30l     185472000 9.3gb
.ds-pypi-1b-s-index_sorting-2024.04.25-000003 0     _2k9     172620000 8.7gb
.ds-pypi-1b-s-index_sorting-2024.04.25-000004 0     _2je     172705000 8.7gb
.ds-pypi-1b-s-index_sorting-2024.04.26-000005 0     _2x0     189458000 9.5gb
.ds-pypi-1b-s-index_sorting-2024.04.26-000006 0     _1nf     116975642 5.9gb

#################################################
GET pypi-1b-s-index_sorting/_count

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
##### With `_source`, Index sorting, `DEFLATE` codec
```
#################################################
GET _data_stream/pypi-1b-s-index_sorting-best_compression/_stats?human=true

{
  "_shards": {
    "total": 5,
    "successful": 5,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 5,
  "total_store_size": "44.7gb",
  "total_store_size_bytes": 48035789015,
  "data_streams": [
    {
      "data_stream": "pypi-1b-s-index_sorting-best_compression",
      "backing_indices": 5,
      "store_size": "44.7gb",
      "store_size_bytes": 48035789015,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-s-index_sorting-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                                          shard segment docs.count  size
.ds-pypi-1b-s-index_sorting-best_compression-2024.04.25-000001 0     _3zf     218601500 9.6gb
.ds-pypi-1b-s-index_sorting-best_compression-2024.04.25-000002 0     _3jp     203318500 8.9gb
.ds-pypi-1b-s-index_sorting-best_compression-2024.04.25-000003 0     _2vn     196172000 8.6gb
.ds-pypi-1b-s-index_sorting-best_compression-2024.04.26-000004 0     _380     214236500 9.4gb
.ds-pypi-1b-s-index_sorting-best_compression-2024.04.26-000005 0     _2qd     180309642 7.9gb

#################################################
GET pypi-1b-s-index_sorting-best_compression/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  }
}
```

##### Without `_source`, Index sorting, `LZ4` codec
```
#################################################
GET _data_stream/pypi-1b-ns-index_sorting/_stats?human=true

{
  "_shards": {
    "total": 5,
    "successful": 5,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 5,
  "total_store_size": "38.3gb",
  "total_store_size_bytes": 41195068059,
  "data_streams": [
    {
      "data_stream": "pypi-1b-ns-index_sorting",
      "backing_indices": 5,
      "store_size": "38.3gb",
      "store_size_bytes": 41195068059,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-ns-index_sorting-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                          shard segment docs.count  size
.ds-pypi-1b-ns-index_sorting-2024.04.25-000001 0     _3pu     218599500 8.2gb
.ds-pypi-1b-ns-index_sorting-2024.04.25-000002 0     _3ki     203320500 7.7gb
.ds-pypi-1b-ns-index_sorting-2024.04.25-000003 0     _36w     217146000 8.2gb
.ds-pypi-1b-ns-index_sorting-2024.04.26-000004 0     _36s     213804000   8gb
.ds-pypi-1b-ns-index_sorting-2024.04.26-000005 0     _2fr     159768142   6gb

#################################################
GET pypi-1b-ns-index_sorting/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  }
}
```

##### Without `_source`, Index sorting, `DEFLATE` codec
```
#################################################
GET _data_stream/pypi-1b-ns-index_sorting-best_compression/_stats?human=true

{
  "_shards": {
    "total": 5,
    "successful": 5,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 5,
  "total_store_size": "36.3gb",
  "total_store_size_bytes": 39020260786,
  "data_streams": [
    {
      "data_stream": "pypi-1b-ns-index_sorting-best_compression",
      "backing_indices": 5,
      "store_size": "36.3gb",
      "store_size_bytes": 39020260786,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-1b-ns-index_sorting-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                                           shard segment docs.count  size
.ds-pypi-1b-ns-index_sorting-best_compression-2024.04.25-000001 0     _46d     218596000 7.8gb
.ds-pypi-1b-ns-index_sorting-best_compression-2024.04.25-000002 0     _3dz     203311000 7.3gb
.ds-pypi-1b-ns-index_sorting-best_compression-2024.04.25-000003 0     _34v     217153000 7.7gb
.ds-pypi-1b-ns-index_sorting-best_compression-2024.04.26-000004 0     _32k     213808000 7.6gb
.ds-pypi-1b-ns-index_sorting-best_compression-2024.04.26-000005 0     _2fs     159770142 5.7gb

#################################################
GET pypi-1b-ns-index_sorting-best_compression/_count

{
  "count": 1012638142,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  }
}
```



#### ClickHouse
##### LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b')
GROUP BY `table`
ORDER BY `table` ASC

Query id: a0b795b3-1598-43d8-9490-19556ce50663

   ┌─table───┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_1b │ 1.01 billion │ 1.00  │ 126.63 GiB             │ 5.24 GiB             │ 5.24 GiB           │
   └─────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

##### ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_zstd')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 5bff60e7-a836-4427-ba2e-e967035b116a

   ┌─table────────┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_1b_zstd │ 1.01 billion │ 1.00  │ 126.63 GiB             │ 3.45 GiB             │ 3.46 GiB           │
   └──────────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

### 1 billion raw data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Without _source, LZ4 codec
```
GET _cat/indices/pypi_1b_by_project?v&h=index,docs.count,pri.store.size&s=index

index              docs.count pri.store.size
pypi_1b_by_project     434776         49.3mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 5536e6e3-fb58-4453-b0e5-8a7204b319b1

   ┌─table──────────────┬─rows────────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_1b_by_project │ 434.78 thousand │ 1.00  │ 9.17 MiB               │ 4.94 MiB             │ 4.94 MiB           │
   └────────────────────┴─────────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

### 1 billion raw data set -  pre-calculated `downloads per country per project` 

#### Elasticsearch - Without _source, LZ4 compression 
```
GET _cat/indices/pypi_1b_by_country_code_project?v&h=index,docs.count,pri.store.size&s=index

index                           docs.count pri.store.size
pypi_1b_by_country_code_project    3523898        355.2mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_country_code_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 9efbf7b2-fba4-4ebf-9907-644b2c8b8c9e

   ┌─table───────────────────────────┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_1b_by_country_code_project │ 3.52 million │ 1.00  │ 76.02 MiB              │ 38.27 MiB            │ 38.28 MiB          │
   └─────────────────────────────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```




### 10 billion raw data set - raw data

#### Elasticsearch

##### With `_source`, No index sorting, `LZ4` codec
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
  "total_store_size_bytes": 1470795110077,
  "data_streams": [
    {
      "data_stream": "pypi-10b-s",
      "backing_indices": 82,
      "store_size": "1.3tb",
      "store_size_bytes": 1470795110077,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-s-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                            shard segment docs.count     size
.ds-pypi-10b-s-2024.04.22-000001 0     _20s     110491500   14.8gb
.ds-pypi-10b-s-2024.04.22-000002 0     _13v     118250500   15.9gb
.ds-pypi-10b-s-2024.04.22-000003 0     _18l     119776000   16.1gb
.ds-pypi-10b-s-2024.04.22-000004 0     _1ad     122074500   16.4gb
.ds-pypi-10b-s-2024.04.22-000005 0     _1fz     127938000   17.2gb
.ds-pypi-10b-s-2024.04.22-000006 0     _17w     132819000   17.8gb
.ds-pypi-10b-s-2024.04.22-000007 0     _1am     126994500   17.1gb
.ds-pypi-10b-s-2024.04.22-000008 0     _189     123822500   16.6gb
.ds-pypi-10b-s-2024.04.22-000009 0     _15r     124548000   16.7gb
.ds-pypi-10b-s-2024.04.22-000010 0     _18m     126420000     17gb
.ds-pypi-10b-s-2024.04.22-000011 0     _187     127798000   17.2gb
.ds-pypi-10b-s-2024.04.22-000012 0     _16o     122384000   16.4gb
.ds-pypi-10b-s-2024.04.22-000013 0     _18g     125307000   16.9gb
.ds-pypi-10b-s-2024.04.22-000014 0     _19v     117937500   15.9gb
.ds-pypi-10b-s-2024.04.22-000015 0     _18p     123227500   16.5gb
.ds-pypi-10b-s-2024.04.22-000016 0     _1d2     125163000   16.8gb
.ds-pypi-10b-s-2024.04.22-000017 0     _197     127606000   17.1gb
.ds-pypi-10b-s-2024.04.23-000018 0     _18v     126668000     17gb
.ds-pypi-10b-s-2024.04.23-000019 0     _16q     126313500     17gb
.ds-pypi-10b-s-2024.04.23-000020 0     _18a     120711500   16.2gb
.ds-pypi-10b-s-2024.04.23-000021 0     _18b     126439000     17gb
.ds-pypi-10b-s-2024.04.23-000022 0     _17z     123366000   16.6gb
.ds-pypi-10b-s-2024.04.23-000023 0     _16j     127077000   17.1gb
.ds-pypi-10b-s-2024.04.23-000024 0     _17m     109681000   14.7gb
.ds-pypi-10b-s-2024.04.23-000025 0     _165     124224000   16.7gb
.ds-pypi-10b-s-2024.04.23-000026 0     _16z     128125500   17.2gb
.ds-pypi-10b-s-2024.04.23-000027 0     _17k     127930000   17.2gb
.ds-pypi-10b-s-2024.04.23-000028 0     _17e     117756500   15.8gb
.ds-pypi-10b-s-2024.04.23-000029 0     _16y     128535000   17.3gb
.ds-pypi-10b-s-2024.04.23-000030 0     _19x     116076500   15.6gb
.ds-pypi-10b-s-2024.04.23-000031 0     _17p     120663500   16.2gb
.ds-pypi-10b-s-2024.04.23-000032 0     _18q     130720000   17.6gb
.ds-pypi-10b-s-2024.04.23-000033 0     _181     117493000   15.8gb
.ds-pypi-10b-s-2024.04.23-000034 0     _159     120670000   16.2gb
.ds-pypi-10b-s-2024.04.23-000035 0     _18v     123187500   16.5gb
.ds-pypi-10b-s-2024.04.23-000036 0     _16o     124803500   16.8gb
.ds-pypi-10b-s-2024.04.23-000037 0     _14c     107763000   14.5gb
.ds-pypi-10b-s-2024.04.23-000038 0     _1sy     127519000   17.1gb
.ds-pypi-10b-s-2024.04.23-000039 0     _1r6     129020500   17.3gb
.ds-pypi-10b-s-2024.04.23-000040 0     _15u     128360000   17.2gb
.ds-pypi-10b-s-2024.04.23-000041 0     _169     116077000   15.6gb
.ds-pypi-10b-s-2024.04.23-000042 0     _150     129540000   17.5gb
.ds-pypi-10b-s-2024.04.23-000043 0     _18f     115461500   15.5gb
.ds-pypi-10b-s-2024.04.23-000044 0     _1gr     113751000   15.3gb
.ds-pypi-10b-s-2024.04.23-000045 0     _17k     118873500     16gb
.ds-pypi-10b-s-2024.04.23-000046 0     _17z     122956500   16.5gb
.ds-pypi-10b-s-2024.04.23-000047 0     _18r     124637500   16.8gb
.ds-pypi-10b-s-2024.04.23-000048 0     _1k0     128154000   17.3gb
.ds-pypi-10b-s-2024.04.23-000049 0     _18u     120307500   16.2gb
.ds-pypi-10b-s-2024.04.23-000050 0     _16b     121448500   16.3gb
.ds-pypi-10b-s-2024.04.23-000051 0     _181     121393000   16.3gb
.ds-pypi-10b-s-2024.04.23-000052 0     _1is     131577500   17.7gb
.ds-pypi-10b-s-2024.04.23-000053 0     _18u     118983500     16gb
.ds-pypi-10b-s-2024.04.23-000054 0     _15y     123732500   16.6gb
.ds-pypi-10b-s-2024.04.23-000055 0     _16z     122203000   16.4gb
.ds-pypi-10b-s-2024.04.23-000056 0     _1cd     128006500   17.2gb
.ds-pypi-10b-s-2024.04.23-000057 0     _16w     121978500   16.4gb
.ds-pypi-10b-s-2024.04.23-000058 0     _16u     131169000   17.6gb
.ds-pypi-10b-s-2024.04.23-000059 0     _1nw     130650500   17.6gb
.ds-pypi-10b-s-2024.04.23-000060 0     _19e     128072000   17.2gb
.ds-pypi-10b-s-2024.04.23-000061 0     _19x     123312500   16.6gb
.ds-pypi-10b-s-2024.04.23-000062 0     _15o     120658000   16.2gb
.ds-pypi-10b-s-2024.04.23-000063 0     _18v     128950500   17.4gb
.ds-pypi-10b-s-2024.04.23-000064 0     _19c     120686500   16.2gb
.ds-pypi-10b-s-2024.04.23-000065 0     _1hj     130777500   17.6gb
.ds-pypi-10b-s-2024.04.23-000066 0     _1c2     116239000   15.6gb
.ds-pypi-10b-s-2024.04.23-000067 0     _1l6     112652000   15.2gb
.ds-pypi-10b-s-2024.04.23-000068 0     _1ao     128072000   17.2gb
.ds-pypi-10b-s-2024.04.23-000069 0     _1g1     126442500     17gb
.ds-pypi-10b-s-2024.04.23-000070 0     _1dr     125529500   16.9gb
.ds-pypi-10b-s-2024.04.23-000071 0     _18k     127034500   17.1gb
.ds-pypi-10b-s-2024.04.23-000072 0     _1bs     127885500   17.2gb
.ds-pypi-10b-s-2024.04.23-000073 0     _183     129472000   17.4gb
.ds-pypi-10b-s-2024.04.23-000074 0     _18t     125950500   16.9gb
.ds-pypi-10b-s-2024.04.23-000075 0     _14b     126221000     17gb
.ds-pypi-10b-s-2024.04.23-000076 0     _18c     115921000   15.6gb
.ds-pypi-10b-s-2024.04.23-000077 0     _1gl     132312500   17.8gb
.ds-pypi-10b-s-2024.04.23-000078 0     _h3       27293910    3.6gb
.ds-pypi-10b-s-2024.04.23-000078 0     _h4        5187282    720mb
.ds-pypi-10b-s-2024.04.23-000078 0     _hp        1864169    271mb
.ds-pypi-10b-s-2024.04.23-000078 0     _id        4652662  659.8mb
.ds-pypi-10b-s-2024.04.23-000078 0     _jf        2102814  303.7mb
.ds-pypi-10b-s-2024.04.23-000078 0     _k5        1559827    227mb
.ds-pypi-10b-s-2024.04.23-000078 0     _kw        5569337  779.7mb
.ds-pypi-10b-s-2024.04.23-000078 0     _m9        2272618  327.9mb
.ds-pypi-10b-s-2024.04.23-000078 0     _n6        2535260  366.5mb
.ds-pypi-10b-s-2024.04.23-000078 0     _pd        5447810  768.9mb
.ds-pypi-10b-s-2024.04.23-000078 0     _py        2843453  407.8mb
.ds-pypi-10b-s-2024.04.23-000078 0     _qt        4776764  669.4mb
.ds-pypi-10b-s-2024.04.23-000078 0     _t7        9074058    1.2gb
.ds-pypi-10b-s-2024.04.23-000078 0     _u6        4092761  576.3mb
.ds-pypi-10b-s-2024.04.23-000078 0     _va        2120275  303.8mb
.ds-pypi-10b-s-2024.04.23-000078 0     _wh        2144357  314.3mb
.ds-pypi-10b-s-2024.04.23-000078 0     _wz        4547707  642.7mb
.ds-pypi-10b-s-2024.04.23-000078 0     _y6        2356542  337.6mb
.ds-pypi-10b-s-2024.04.23-000078 0     _z5        2000353    286mb
.ds-pypi-10b-s-2024.04.23-000078 0     _15f      27656041    3.7gb
.ds-pypi-10b-s-2024.04.23-000079 0     _f8       22286922      3gb
.ds-pypi-10b-s-2024.04.23-000079 0     _l1        2084203  297.2mb
.ds-pypi-10b-s-2024.04.23-000079 0     _m6       21956305    2.9gb
.ds-pypi-10b-s-2024.04.23-000079 0     _mx        3914023  550.7mb
.ds-pypi-10b-s-2024.04.23-000079 0     _nq        1711737  254.4mb
.ds-pypi-10b-s-2024.04.23-000079 0     _oz        3383941  484.9mb
.ds-pypi-10b-s-2024.04.23-000079 0     _q1        5273505  744.9mb
.ds-pypi-10b-s-2024.04.23-000079 0     _rs        2542585  361.1mb
.ds-pypi-10b-s-2024.04.23-000079 0     _s9        4150158    592mb
.ds-pypi-10b-s-2024.04.23-000079 0     _ti        4380608  626.1mb
.ds-pypi-10b-s-2024.04.23-000079 0     _ub        2458399  349.3mb
.ds-pypi-10b-s-2024.04.23-000079 0     _17v      51054114    6.9gb
.ds-pypi-10b-s-2024.04.23-000080 0     _hp       26091063    3.5gb
.ds-pypi-10b-s-2024.04.23-000080 0     _mw         804782  120.8mb
.ds-pypi-10b-s-2024.04.23-000080 0     _n4         349442   55.3mb
.ds-pypi-10b-s-2024.04.23-000080 0     _n5         217143   35.3mb
.ds-pypi-10b-s-2024.04.23-000080 0     _n7         245243   39.6mb
.ds-pypi-10b-s-2024.04.23-000080 0     _n8         230693   37.2mb
.ds-pypi-10b-s-2024.04.23-000080 0     _nc         386620     61mb
.ds-pypi-10b-s-2024.04.23-000080 0     _nr       23923674    3.2gb
.ds-pypi-10b-s-2024.04.23-000080 0     _p0        2159361    311mb
.ds-pypi-10b-s-2024.04.23-000080 0     _ri        7829757      1gb
.ds-pypi-10b-s-2024.04.23-000080 0     _sy        3557258  510.6mb
.ds-pypi-10b-s-2024.04.23-000080 0     _tu        5181404  724.1mb
.ds-pypi-10b-s-2024.04.23-000080 0     _y3        3598937  512.3mb
.ds-pypi-10b-s-2024.04.23-000080 0     _yz        7190618 1009.3mb
.ds-pypi-10b-s-2024.04.23-000080 0     _10d       2557487  364.1mb
.ds-pypi-10b-s-2024.04.23-000080 0     _11i       3969018  561.8mb
.ds-pypi-10b-s-2024.04.23-000080 0     _12j       6905435  976.1mb
.ds-pypi-10b-s-2024.04.23-000080 0     _13l       2153940  309.2mb
.ds-pypi-10b-s-2024.04.23-000080 0     _13x       4068804  575.1mb
.ds-pypi-10b-s-2024.04.23-000080 0     _17d       9071093    1.2gb
.ds-pypi-10b-s-2024.04.23-000080 0     _188       6805939  953.2mb
.ds-pypi-10b-s-2024.04.23-000080 0     _18p       4310906  615.6mb
.ds-pypi-10b-s-2024.04.23-000080 0     _18t        184886     30mb
.ds-pypi-10b-s-2024.04.23-000080 0     _18w        237195   37.8mb
.ds-pypi-10b-s-2024.04.23-000080 0     _194       3599302  505.8mb
.ds-pypi-10b-s-2024.04.23-000081 0     _so       71036773    9.5gb
.ds-pypi-10b-s-2024.04.23-000081 0     _sx        3047417  434.2mb
.ds-pypi-10b-s-2024.04.23-000081 0     _u3        1840875  264.1mb
.ds-pypi-10b-s-2024.04.23-000081 0     _uq        7181796   1014mb
.ds-pypi-10b-s-2024.04.23-000081 0     _wk        3988017  560.6mb
.ds-pypi-10b-s-2024.04.23-000081 0     _wr        3798053  539.3mb
.ds-pypi-10b-s-2024.04.23-000081 0     _x8        3852284  549.2mb
.ds-pypi-10b-s-2024.04.23-000081 0     _yf        3945178  560.7mb
.ds-pypi-10b-s-2024.04.23-000081 0     _108       4132951    577mb
.ds-pypi-10b-s-2024.04.23-000081 0     _119       5168361  730.5mb
.ds-pypi-10b-s-2024.04.23-000081 0     _12l       2829317  407.9mb
.ds-pypi-10b-s-2024.04.23-000081 0     _139       6344697  878.5mb
.ds-pypi-10b-s-2024.04.23-000081 0     _13w         58035   10.3mb
.ds-pypi-10b-s-2024.04.23-000081 0     _14d       1353217    194mb

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
##### Without `_source`, No index sorting, `LZ4` codec
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
  "total_store_size": "373.9gb",
  "total_store_size_bytes": 401489958522,
  "data_streams": [
    {
      "data_stream": "pypi-10b-ns",
      "backing_indices": 53,
      "store_size": "373.9gb",
      "store_size_bytes": 401489958522,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-ns-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                             shard segment docs.count  size
.ds-pypi-10b-ns-2024.04.22-000001 0     _2w5     228727000 8.5gb
.ds-pypi-10b-ns-2024.04.22-000002 0     _1rh     178243500 6.6gb
.ds-pypi-10b-ns-2024.04.22-000003 0     _1te     191560000 7.1gb
.ds-pypi-10b-ns-2024.04.22-000004 0     _1vg     194514500 7.2gb
.ds-pypi-10b-ns-2024.04.22-000005 0     _1ox     189106500   7gb
.ds-pypi-10b-ns-2024.04.22-000006 0     _1s6     186727500 6.9gb
.ds-pypi-10b-ns-2024.04.22-000007 0     _1rz     192047000 7.1gb
.ds-pypi-10b-ns-2024.04.22-000008 0     _1pc     181723500 6.7gb
.ds-pypi-10b-ns-2024.04.22-000009 0     _1rl     183896500 6.8gb
.ds-pypi-10b-ns-2024.04.22-000010 0     _1q2     188222000   7gb
.ds-pypi-10b-ns-2024.04.22-000011 0     _1sg     187789500   7gb
.ds-pypi-10b-ns-2024.04.23-000012 0     _1r1     191362500 7.1gb
.ds-pypi-10b-ns-2024.04.23-000013 0     _1q1     182315500 6.8gb
.ds-pypi-10b-ns-2024.04.23-000014 0     _1ph     192329000 7.1gb
.ds-pypi-10b-ns-2024.04.23-000015 0     _1wb     184553000 6.9gb
.ds-pypi-10b-ns-2024.04.23-000016 0     _1sw     172540000 6.4gb
.ds-pypi-10b-ns-2024.04.23-000017 0     _1p5     189490500   7gb
.ds-pypi-10b-ns-2024.04.23-000018 0     _1t3     186351500 6.9gb
.ds-pypi-10b-ns-2024.04.23-000019 0     _2bc     246814500 9.1gb
.ds-pypi-10b-ns-2024.04.23-000020 0     _2bt     242481000   9gb
.ds-pypi-10b-ns-2024.04.23-000021 0     _1tn     183527500 6.8gb
.ds-pypi-10b-ns-2024.04.23-000022 0     _1qs     185087000 6.9gb
.ds-pypi-10b-ns-2024.04.23-000023 0     _1sz     183574000 6.8gb
.ds-pypi-10b-ns-2024.04.23-000024 0     _1q7     170948500 6.3gb
.ds-pypi-10b-ns-2024.04.23-000025 0     _25o     193354000 7.2gb
.ds-pypi-10b-ns-2024.04.23-000026 0     _1o4     183611500 6.8gb
.ds-pypi-10b-ns-2024.04.23-000027 0     _1ra     190365500 7.1gb
.ds-pypi-10b-ns-2024.04.23-000028 0     _1th     169727500 6.3gb
.ds-pypi-10b-ns-2024.04.23-000029 0     _1t4     178358500 6.6gb
.ds-pypi-10b-ns-2024.04.23-000030 0     _1vk     188202000   7gb
.ds-pypi-10b-ns-2024.04.23-000031 0     _2gd     245283000 9.1gb
.ds-pypi-10b-ns-2024.04.23-000032 0     _1qx     184019000 6.8gb
.ds-pypi-10b-ns-2024.04.23-000033 0     _1t7     187466000   7gb
.ds-pypi-10b-ns-2024.04.23-000034 0     _1tn     184488000 6.8gb
.ds-pypi-10b-ns-2024.04.23-000035 0     _1su     184503000 6.9gb
.ds-pypi-10b-ns-2024.04.23-000036 0     _1s3     189439000   7gb
.ds-pypi-10b-ns-2024.04.23-000037 0     _1pn     185800500 6.9gb
.ds-pypi-10b-ns-2024.04.23-000038 0     _1v8     197997500 7.3gb
.ds-pypi-10b-ns-2024.04.23-000039 0     _1sr     189444500   7gb
.ds-pypi-10b-ns-2024.04.23-000040 0     _1ns     182612500 6.8gb
.ds-pypi-10b-ns-2024.04.23-000041 0     _1ry     193063000 7.2gb
.ds-pypi-10b-ns-2024.04.23-000042 0     _1t0     187342500 6.9gb
.ds-pypi-10b-ns-2024.04.23-000043 0     _1uj     168749000 6.3gb
.ds-pypi-10b-ns-2024.04.23-000044 0     _1tr     188218500   7gb
.ds-pypi-10b-ns-2024.04.23-000045 0     _1py     190888000 7.1gb
.ds-pypi-10b-ns-2024.04.23-000046 0     _29y     252997500 9.4gb
.ds-pypi-10b-ns-2024.04.23-000047 0     _17m     129914500 4.8gb
.ds-pypi-10b-ns-2024.04.23-000048 0     _1x1     188511500   7gb
.ds-pypi-10b-ns-2024.04.23-000049 0     _1rj     183570500 6.8gb
.ds-pypi-10b-ns-2024.04.23-000050 0     _1uc     190892000 7.1gb
.ds-pypi-10b-ns-2024.04.23-000051 0     _1u8     182102000 6.8gb
.ds-pypi-10b-ns-2024.04.23-000052 0     _1pk     188807500   7gb
.ds-pypi-10b-ns-2024.04.23-000053 0     _15m     118591971 4.4gb


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
##### With `_source`, Index sorting, `LZ4` codec
```
#################################################
GET _data_stream/pypi-10b-s-index_sorting/_stats?human=true

{
  "_shards": {
    "total": 58,
    "successful": 58,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 58,
  "total_store_size": "500.7gb",
  "total_store_size_bytes": 537663435910,
  "data_streams": [
    {
      "data_stream": "pypi-10b-s-index_sorting",
      "backing_indices": 58,
      "store_size": "500.7gb",
      "store_size_bytes": 537663435910,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-s-index_sorting-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                          shard segment docs.count    size
.ds-pypi-10b-s-index_sorting-2024.04.26-000001 0     _2dq     174859500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000002 0     _1t2     178617000   8.9gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000003 0     _1lj     172798500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000004 0     _224     209459500  10.4gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000005 0     _1qd     169734500   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000006 0     _1nr     172021000   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.26-000007 0     _1m9     176094000   8.8gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000008 0     _1ok     168770500   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000009 0     _1mz     174009500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000010 0     _1z2     204780000  10.1gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000011 0     _1ld     175783500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000012 0     _1nb     170941500   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000013 0     _206     172043500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000014 0     _1mc     174944500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000015 0     _1mi     173727500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000016 0     _1o4     167157500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000017 0     _1o1     168932000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000018 0     _1qp     170033500   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000019 0     _1un     168456000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000020 0     _1l8     172513000   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000021 0     _23o     205642000  10.2gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000022 0     _1lx     171037000   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000023 0     _22o     204269500  10.1gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000024 0     _1pw     173909500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000025 0     _1ol     167083500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000026 0     _1nx     167820000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000027 0     _1n2     172155500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000028 0     _1pb     169251000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000029 0     _233     204868500  10.1gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000030 0     _1nf     174689500   8.7gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000031 0     _1q6     165013000   8.2gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000032 0     _1nb     166924500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000033 0     _1s7     173617500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000034 0     _1n9     164585500   8.2gb
.ds-pypi-10b-s-index_sorting-2024.04.27-000035 0     _1js     173348500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000036 0     _1qi     169820500   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000037 0     _1pk     170016500   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000038 0     _1lk     168849500   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000039 0     _1qq     172494500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000040 0     _1lf     171062000   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000041 0     _1mu     165688000   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000042 0     _1ot     173053500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000043 0     _31e     166521500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000044 0     _1ry     165656500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000045 0     _1oe     170981000   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000046 0     _21n     203779000  10.1gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000047 0     _1ns     167126500   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000048 0     _1or     169385000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000049 0     _1m0     173274000   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000050 0     _22r     202612500    10gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000051 0     _28s     202889000    10gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000052 0     _1ov     176032500   8.8gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000053 0     _1ns     167885500   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000054 0     _2fo     170549000   8.5gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000055 0     _1sy     167458000   8.3gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000056 0     _1pa     168174000   8.4gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000057 0     _1pv     172712500   8.6gb
.ds-pypi-10b-s-index_sorting-2024.04.28-000058 0     _8f        6339971 367.4mb

#################################################
GET pypi-10b-s-index_sorting/_count
{
  "count": 10012252471,
  "_shards": {
    "total": 58,
    "successful": 58,
    "skipped": 0,
    "failed": 0
  }
}
```
##### With `_source`, Index sorting, `DEFLATE` codec
```
#################################################
GET _data_stream/pypi-10b-s-index_sorting-best_compression/_stats?human=true

{
  "_shards": {
    "total": 49,
    "successful": 49,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 49,
  "total_store_size": "469.3gb",
  "total_store_size_bytes": 503978432885,
  "data_streams": [
    {
      "data_stream": "pypi-10b-s-index_sorting-best_compression",
      "backing_indices": 49,
      "store_size": "469.3gb",
      "store_size_bytes": 503978432885,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-s-index_sorting-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                                           shard segment docs.count   size
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000001 0     _1r4     210065000  9.1gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000002 0     _1uv     212240500  9.2gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000003 0     _1x3     209858000  9.1gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000004 0     _1wp     205777500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000005 0     _1wz     207220500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.26-000006 0     _1xc     208408000    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000007 0     _1xu     202986500  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000008 0     _1xb     206624500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000009 0     _1wv     207354000    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000010 0     _20b     208179500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000011 0     _1wx     208151500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000012 0     _1ww     207991500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000013 0     _1yu     207138000    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000014 0     _1xr     199008500  8.6gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000015 0     _1wo     206787000    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000016 0     _2cc     235358000 10.2gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000017 0     _1zd     204982500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000018 0     _1u1     207432500    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000019 0     _1zz     203570000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000020 0     _1zc     205767500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000021 0     _1y3     207877000    9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000022 0     _1yr     200355000  8.7gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000023 0     _1wc     204460500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000024 0     _1un     203303500  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000025 0     _1yg     204587000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000026 0     _1yx     205741500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000027 0     _21s     201921500  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000028 0     _1xb     205364000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000029 0     _2aj     231251000   10gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.27-000030 0     _1wm     209825000  9.1gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000031 0     _20a     204601000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000032 0     _1yq     202006500  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000033 0     _1xe     204863000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000034 0     _1vc     202698000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000035 0     _1vd     203623500  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000036 0     _1y6     201751000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000037 0     _1zd     200913500  8.7gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000038 0     _21l     203991500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000039 0     _1zg     203765500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000040 0     _1ym     200843000  8.7gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000041 0     _1w4     204203500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000042 0     _1vj     203317000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000043 0     _1x6     206012500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000044 0     _207     205955500  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000045 0     _1z7     204519000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000046 0     _1wl     204917000  8.9gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000047 0     _1y5     202141000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000048 0     _1xv     202266000  8.8gb
.ds-pypi-10b-s-index_sorting-best_compression-2024.04.28-000049 0     _12z     110277471  4.9gb

#################################################
GET pypi-10b-s-index_sorting-best_compression/_count

{
  "count": 10012252471,
  "_shards": {
    "total": 49,
    "successful": 49,
    "skipped": 0,
    "failed": 0
  }
}
```

##### Without `_source`, Index sorting, `LZ4` codec
```
#################################################
GET _data_stream/pypi-10b-ns-index_sorting/_stats?human=true

{
  "_shards": {
    "total": 48,
    "successful": 48,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 48,
  "total_store_size": "374.9gb",
  "total_store_size_bytes": 402573259709,
  "data_streams": [
    {
      "data_stream": "pypi-10b-ns-index_sorting",
      "backing_indices": 48,
      "store_size": "374.9gb",
      "store_size_bytes": 402573259709,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-ns-index_sorting-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                           shard segment docs.count  size
.ds-pypi-10b-ns-index_sorting-2024.04.26-000001 0     _1r2     210063000 7.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.26-000002 0     _223     212242500 7.9gb
.ds-pypi-10b-ns-index_sorting-2024.04.26-000003 0     _24r     209858000 7.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.26-000004 0     _1ze     205762500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.26-000005 0     _1yf     207232500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.26-000006 0     _20w     208411000 7.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000007 0     _24n     202985500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000008 0     _22c     206615000 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000009 0     _206     207349500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000010 0     _25f     208179500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000011 0     _22t     208160000 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000012 0     _20b     207984500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000013 0     _22l     207151500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000014 0     _2dc     232482500 8.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000015 0     _1yo     207351500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000016 0     _2e7     235701500 8.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000017 0     _20r     203027500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000018 0     _23m     207271500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000019 0     _1zq     203644000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000020 0     _20s     207908500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000021 0     _1zw     204699000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000022 0     _20v     201346000 7.5gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000023 0     _23n     203596000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000024 0     _20f     206374000 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000025 0     _21r     204029500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000026 0     _1zs     205305000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000027 0     _2e1     233608500 8.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000028 0     _20p     205758500 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000029 0     _2e6     236355500 8.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.27-000030 0     _22d     205133500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000031 0     _24t     204135500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000032 0     _21m     201766000 7.5gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000033 0     _1zb     207584000 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000034 0     _2dn     234852000 8.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000035 0     _20u     206936000 7.7gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000036 0     _2bv     231093000 8.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000037 0     _23f     202999000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000038 0     _21w     203448500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000039 0     _205     203526500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000040 0     _216     202382500 7.5gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000041 0     _234     205353500 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000042 0     _21z     205512000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000043 0     _25n     201747000 7.5gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000044 0     _1zx     210159000 7.8gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000045 0     _1yy     203670000 7.6gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000046 0     _1zs     199866000 7.4gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000047 0     _20l     202582000 7.5gb
.ds-pypi-10b-ns-index_sorting-2024.04.28-000048 0     _1ru     179052471 6.7gb

#################################################
GET pypi-10b-ns-index_sorting/_count

{
  "count": 10012252471,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  }
}
```

##### Without `_source`, Index sorting, `DEFLATE` codec
```
#################################################
GET _data_stream/pypi-10b-ns-index_sorting-best_compression/_stats?human=true

{
  "_shards": {
    "total": 48,
    "successful": 48,
    "failed": 0
  },
  "data_stream_count": 1,
  "backing_indices": 48,
  "total_store_size": "355gb",
  "total_store_size_bytes": 381264723814,
  "data_streams": [
    {
      "data_stream": "pypi-10b-ns-index_sorting-best_compression",
      "backing_indices": 48,
      "store_size": "355gb",
      "store_size_bytes": 381264723814,
      "maximum_timestamp": 1687509239000
    }
  ]
}

#################################################
GET _cat/segments/.ds-pypi-10b-ns-index_sorting-best_compression-2024*?v=true&h=index,shard,segment,docs.count,size&s=index

index                                                            shard segment docs.count  size
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000001 0     _1xl     210063000 7.4gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000002 0     _1vn     212242500 7.5gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000003 0     _1yl     209851000 7.4gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000004 0     _1vk     205769500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000005 0     _1we     207232500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.26-000006 0     _1wf     208411000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000007 0     _1tz     202985500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000008 0     _1w4     206610500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000009 0     _1wv     207354000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000010 0     _211     208179500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000011 0     _1zi     208151500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000012 0     _1vk     207991500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000013 0     _1vh     207151000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000014 0     _28u     232484500 8.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000015 0     _1ys     207341500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000016 0     _23z     201329500 7.1gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000017 0     _1ts     204975000 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000018 0     _1wf     207427500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000019 0     _1wd     203567500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000020 0     _1zo     205782500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000021 0     _1u7     207873500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000022 0     _2a4     232652500 8.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000023 0     _1ue     203596000 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000024 0     _1z3     206359000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000025 0     _200     204043000 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000026 0     _210     205291500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000027 0     _2b7     233609500 8.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000028 0     _1wu     205757500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000029 0     _2eq     236355500 8.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.27-000030 0     _1z4     205148500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000031 0     _1w6     204135500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000032 0     _20s     201766000 7.1gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000033 0     _1ua     207569000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000034 0     _28d     234852500 8.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000035 0     _20c     206950500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000036 0     _2cj     231087500 8.1gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000037 0     _1zl     203003000 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000038 0     _1zb     203450000 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000039 0     _1vv     203526500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000040 0     _2c0     234870500 8.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000041 0     _21j     206768000 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000042 0     _1yk     206294500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000043 0     _2bx     238256000 8.4gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000044 0     _1vo     204528500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000045 0     _1u9     204907500 7.2gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000046 0     _29v     234984500 8.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000047 0     _1xj     205664500 7.3gb
.ds-pypi-10b-ns-index_sorting-best_compression-2024.04.28-000048 0     _tm       74050471 2.6gb


#################################################
GET pypi-10b-ns-index_sorting-best_compression/_count

{
  "count": 10012252471,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  }
}
```



#### ClickHouse
##### LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 13fc1d1d-cc5f-4604-8621-17ecad3927fa

   ┌─table────┬─rows──────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_10b │ 10.01 billion │ 1.00  │ 1.22 TiB               │ 39.10 GiB            │ 39.12 GiB          │
   └──────────┴───────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```
##### ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_zstd')
GROUP BY `table`
ORDER BY `table` ASC

Query id: cf771596-1b63-4fae-861c-eb24b5c418bc

   ┌─table─────────┬─rows──────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_10b_zstd │ 10.01 billion │ 1.00  │ 1.22 TiB               │ 23.43 GiB            │ 23.45 GiB          │
   └───────────────┴───────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

### 10 billion raw data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Without _source, LZ4 codec
```
GET _cat/indices/pypi_10b_by_project?v&h=index,docs.count,pri.store.size&s=index

index               docs.count pri.store.size
pypi_10b_by_project     465978           48mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: f8e7d78d-1a70-4f66-9845-f324ed43674c

   ┌─table───────────────┬─rows────────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_10b_by_project │ 465.98 thousand │ 1.00  │ 9.85 MiB               │ 5.39 MiB             │ 5.39 MiB           │
   └─────────────────────┴─────────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

### 10 billion raw data set -  pre-calculated `downloads per country per project` 

#### Elasticsearch - Without _source, LZ4 compression 
```
GET _cat/indices/pypi_10b_by_country_code_project?v&h=index,docs.count,pri.store.size&s=index

index                            docs.count pri.store.size
pypi_10b_by_country_code_project    8785501        715.2mb
```

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_10b_by_country_code_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 047886ce-65df-43a4-891f-7e681797e81c

   ┌─table────────────────────────────┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_10b_by_country_code_project │ 8.79 million │ 1.00  │ 190.99 MiB             │ 97.46 MiB            │ 97.48 MiB          │
   └──────────────────────────────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```


### 100 billion raw data set - raw data

#### Elasticsearch

We were unable to load the 100 billion row raw data set into Elasticsearch.

After around ~33 billion rows were loaded:
```
GET pypi-100b-s-index_sorting-best_compression/_count

{
  "count": 33468629551,
  "_shards": {
    "total": 140,
    "successful": 140,
    "skipped": 0,
    "failed": 0
  }
}
```

We saw these errors in the Logstash log file:
```
Could not index event to Elasticsearch. {:status=>400, :action=>["create", {:_id=>nil, :_index=>"pypi-100b-s-index_sorting-best_compression", :routing=>nil}, {"project"=>"selenium", "url"=>"/packages/ad/13/481aa476a9bcfec0bf74140a4c395dede0569cf56dc773abec181f95e30f/selenium-4.8.2-py3-none-any.whl", "@timestamp"=>2023-06-06T12:30:42.000Z, "country_code"=>"US"}], :response=>{"create"=>{"status"=>400, "error"=>{"type"=>"illegal_argument_exception", "reason"=>"Number of documents in the index can't exceed [2147483519]"}}}}
```

We checked the data streams backing indexes:

```
GET _cat/indices/pypi-100b-s-index_sorting-best_compression?v&h=index,docs.count,pri.store.size&s=index

index                                                            docs.count pri.store.size
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000001  226110000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000002  208063000          6.9gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000003  210318500          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000004  206342000          6.9gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000005  207745500          6.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000006  208163500          6.9gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000007  215392500          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000008  225005378          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000009  224320500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000010  216945500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000011  229552000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000012  225581000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000013  227976500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.04.30-000014  227333500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000015  225968500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000016  226970092          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000017  226702000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000018  224236000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000019  226056000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000020  226063500          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000021  222471000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000022  227171000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000023  222934000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000024  224789500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000025  224684000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000026  230531000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000027  222988500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000028  224434000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000029  226094500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000030  224709500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000031  222474500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000032  227271500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000033  220090500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000034  224165000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000035  223502500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000036  226700500          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000037  223764500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.01-000038  230172000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000039  221284000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000040  226085500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000041  224433500          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000042  220238000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000043  222270000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000044  227239000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000045  226766000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000046  222485000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000047  223730500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000048  221380000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000049  222597500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000050  223378000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000051  226011000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000052  223718000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000053  224346000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000054  222780500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000055  227359781          7.9gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000056  222659000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000057  221981500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000058  224107500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000059  227520000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000060  229349500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000061  227503500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.02-000062  225695500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000063  227475500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000064  226146000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000065  225576000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000066  230947000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000067  225554000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000068  223799500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000069  224728500          7.9gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000070  223708500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000071  225571000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000072  225219000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000073  225604500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000074  227605500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000075  223231000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000076  223064500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000077  223632500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000078  222916000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000079  227579500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000080  227698000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000081  226887500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000082  226328000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000083  227514000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000084  229218000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000085  224195000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.03-000086  226409500          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000087  221832000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000088  221613500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000089  223609500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000090  222027500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000091  229968500          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000092  226618000          7.8gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000093  223659000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000094  224583500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000095  225984000          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000096  227032500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000097  225505000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000098  224614000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000099  226785500          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000100  227338500          7.6gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000101  222111000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000102  226276000          7.7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000103  220565000          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000104  224162500          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000105  226442000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000106  230829500          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000107  228166000            7gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000108  231724500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000109  227104500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.04-000110  231365500          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000111  234006500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000112  230199000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000113  227686500          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000114  229071000          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000115  227037500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000116  225789500          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000117  230545000          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000118  232117500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000119  230338500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000120  231865500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000121  229876500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000122  226165500          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000123  226373500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000124  229145500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000125  230731500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000126  229995000          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000127  227330000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000128  230465500          7.3gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000129  231035000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000130  231381000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000131  225923500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000132  227625500          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000133  227144000          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.05-000134  224698500          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000135  225669281          7.4gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000136  225421500          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000137  227675000          7.1gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000138  230700000          7.5gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000139  225895000          7.2gb
.ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000140 2147483519         68.1gb
```

The last (current) backing index couldn't be rolled over:
```
GET /pypi-100b-s-index_sorting-best_compression/_ilm/explain

".ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000140": {
  "index": ".ds-pypi-100b-s-index_sorting-best_compression-2024.05.06-000140",
  "managed": true,
  "policy": "pypi-lifecycle-policy",
  "index_creation_date_millis": 1714972568020,
  "time_since_index_creation": "1.1d",
  "lifecycle_date_millis": 1714972568020,
  "age": "1.1d",
  "phase": "hot",
  "phase_time_millis": 1715067966540,
  "action": "rollover",
  "action_time_millis": 1714972568285,
  "step": "ERROR",
  "step_time_millis": 1715067966740,
  "failed_step": "attempt-rollover",
  "is_auto_retryable_error": true,
  "failed_step_retry_count": 153,
  "step_info": {
    "type": "validation_exception",
    "reason": "Validation Failed: 1: this action would add [1] shards, but this cluster currently has [1000]/[1000] maximum normal shards open;"
  },
  "phase_execution": {
    "policy": "pypi-lifecycle-policy",
    "phase_definition": {
      "min_age": "0ms",
      "actions": {
        "rollover": {
          "max_primary_shard_docs": 200000000,
          "max_primary_shard_size": "10gb"
        },
        "forcemerge": {
          "max_num_segments": 1
        }
      }
    },
    "version": 2,
    "modified_date_in_millis": 1714464574210
  }
```

However, the `Total shards per node`  setting is unbounded by [default](https://www.elastic.co/guide/en/elasticsearch/reference/current/allocation-total-shards.html).

We checked this on our node:
```
GET _cluster/settings?include_defaults=true

"allocation": {
  "enforce_default_tier_preference": "true",
  "node_concurrent_incoming_recoveries": "2",
  "node_initial_primaries_recoveries": "4",
  "desired_balance": {
    "progress_log_interval": "1m",
    "undesired_allocations": {
      "log_interval": "1h",
      "threshold": "0.1"
    }
  },
  "same_shard": {
    "host": "false"
  },
  "total_shards_per_node": "-1",
  "type": "desired_balance",
  "disk": {
    "threshold_enabled": "true",
    "reroute_interval": "60s",
    "watermark": {
      "flood_stage.frozen.max_headroom": "20GB",
      "flood_stage": "95%",
      "high": "90%",
      "low": "85%",
      "flood_stage.frozen": "95%",
      "flood_stage.max_headroom": "100GB",
      "low.max_headroom": "200GB",
      "enable_for_single_data_node": "true",
      "high.max_headroom": "150GB"
    }
  }

```

The above shows: `"total_shards_per_node": "-1"`.

We gave up for now.


#### ClickHouse
##### LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_100b')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 67a1e722-83cd-41f2-96a9-6a51c20dde43

   ┌─table─────┬─rows───────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_100b │ 110.21 billion │ 16.00 │ 13.46 TiB              │ 384.28 GiB           │ 384.54 GiB         │
   └───────────┴────────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```
##### ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_100b_zstd')
GROUP BY `table`
ORDER BY `table` ASC

Query id: fcca179c-d508-481a-9461-53a086899f8b

   ┌─table──────────┬─rows───────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_100b_zstd │ 110.21 billion │ 15.00 │ 13.46 TiB              │ 131.91 GiB           │ 132.11 GiB         │
   └────────────────┴────────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘

```

### 100 billion raw data set -  pre-calculated `downloads per project` 

#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_100b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 97c09350-5153-45e1-b9bd-b55bc45679c8

   ┌─table────────────────┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_100b_by_project │ 1.33 million │ 5.00  │ 28.01 MiB              │ 15.16 MiB            │ 15.16 MiB          │
   └──────────────────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```

### 100 billion raw data set -  pre-calculated `downloads per country per project` 


#### ClickHouse - LZ4 compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_100b_by_country_code_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 0a441e48-f5a4-4779-bcdb-b1e625018d42

   ┌─table─────────────────────────────┬─rows──────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_100b_by_country_code_project │ 41.47 million │ 9.00  │ 899.31 MiB             │ 457.70 MiB           │ 457.79 MiB         │
   └───────────────────────────────────┴───────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```


## Query runtimes

### 1 billion raw data set - raw data - downloads per project

#### Elasticsearch - Query DSL
#####  Index with index sorting (and without `_source`)

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 


```
#################################################

GET pypi-1b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 3207,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8702702,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}

#################################################

GET pypi-1b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 3850,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8702702,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}


#################################################

GET pypi-1b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 3444,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8702702,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}
```


#####  Index without index sorting (and without `_source`)

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 


```
#################################################

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

{
  "took": 9101,
  "timed_out": false,
  "_shards": {
    "total": 6,
    "successful": 6,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8705840,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}

#################################################

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

{
  "took": 9045,
  "timed_out": false,
  "_shards": {
    "total": 6,
    "successful": 6,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8705840,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}



#################################################

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

{
  "took": 9039,
  "timed_out": false,
  "_shards": {
    "total": 6,
    "successful": 6,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 8705840,
      "sum_other_doc_count": 954052769,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 28202786
        },
        {
          "key": "urllib3",
          "doc_count": 15992012
        },
        {
          "key": "requests",
          "doc_count": 14390575
        }
      ]
    }
  }
}

```

#### Elasticsearch - ESQL

#####  Index with index sorting (and without `_source`)

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests 

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [6206]ms


#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}
     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests  

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [8091]ms
 
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests   

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [6078]ms
    

```

#####  Index without index sorting (and without `_source`)

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests 

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9574]ms


#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}
     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests  

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9584]ms
 
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
28202786       |boto3          
15992012       |urllib3        
14390575       |requests   

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9498]ms
    

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

Query id: d7652710-7ecb-4630-a59b-c9ef8feffa7f

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.716 sec. Processed 1.01 billion rows, 19.08 GB (1.41 billion rows/s., 26.65 GB/s.)
Peak memory usage: 336.67 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 024b4589-6444-4070-a088-588b4884c637

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.720 sec. Processed 1.01 billion rows, 19.08 GB (1.41 billion rows/s., 26.50 GB/s.)
Peak memory usage: 333.72 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 0cc8fd8e-f0b9-4eca-bb54-d472392d6062

   ┌─project──┬────count─┐
1. │ boto3    │ 28202786 │
2. │ urllib3  │ 15992012 │
3. │ requests │ 14390575 │
   └──────────┴──────────┘

3 rows in set. Elapsed: 0.719 sec. Processed 1.01 billion rows, 19.08 GB (1.41 billion rows/s., 26.51 GB/s.)
Peak memory usage: 319.72 MiB.
```

#### ClickHouse Cloud - 1 node with 8 CPU cores per node - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 8, enable_filesystem_cache = 0, use_query_cache = 0

Query id: b9954d7b-65d9-4a9e-ad2d-dbc750381391

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 2.763 sec. Processed 1.01 billion rows, 19.08 GB (366.50 million rows/s., 6.90 GB/s.)
Peak memory usage: 183.06 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 8, enable_filesystem_cache = 0, use_query_cache = 0

Query id: eded7506-6dc2-4cc2-9607-21b4589ba8a5

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 2.782 sec. Processed 1.01 billion rows, 19.08 GB (363.98 million rows/s., 6.86 GB/s.)
Peak memory usage: 188.57 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 8, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 5c90d72c-d8d2-4ab5-b629-047f83da07f6

┌─project──┬────count─┐
│ boto3    │ 28202786 │
│ urllib3  │ 15992012 │
│ requests │ 14390575 │
└──────────┴──────────┘

3 rows in set. Elapsed: 2.754 sec. Processed 1.01 billion rows, 19.08 GB (367.71 million rows/s., 6.93 GB/s.)
Peak memory usage: 186.00 MiB.

```

### 1 billion raw data set - raw data - downloads per project for a specific country

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
GET pypi-1b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}

{
  "took": 232,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 243399,
      "sum_other_doc_count": 31164813,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 617810
        },
        {
          "key": "typing-extensions",
          "doc_count": 562834
        },
        {
          "key": "pyjwt",
          "doc_count": 441337
        }
      ]
    }
  }
}
#################################################
GET pypi-1b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}

{
  "took": 247,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 243399,
      "sum_other_doc_count": 31164813,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 617810
        },
        {
          "key": "typing-extensions",
          "doc_count": 562834
        },
        {
          "key": "pyjwt",
          "doc_count": 441337
        }
      ]
    }
  }
}

#################################################
GET pypi-1b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}


{
  "took": 290,
  "timed_out": false,
  "_shards": {
    "total": 5,
    "successful": 5,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 243399,
      "sum_other_doc_count": 31164813,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 617810
        },
        {
          "key": "typing-extensions",
          "doc_count": 562834
        },
        {
          "key": "pyjwt",
          "doc_count": 441337
        }
      ]
    }
  }
}

```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |     project     
---------------+-----------------
617810         |cryptography     
562834         |typing-extensions
441337         |pyjwt 

Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9278]ms

#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}


     count     |     project     
---------------+-----------------
617810         |cryptography     
562834         |typing-extensions
441337         |pyjwt    


Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9265]ms

#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}


     count     |     project     
---------------+-----------------
617810         |cryptography     
562834         |typing-extensions
441337         |pyjwt    


Finished execution of ESQL query.
Query string: [
    FROM pypi-1b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [9285]ms


```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: dc78a62a-0ee0-4503-8f2e-6558d07f6e43

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.043 sec. Processed 32.79 million rows, 689.60 MB (769.55 million rows/s., 16.18 GB/s.)
Peak memory usage: 18.90 MiB.


------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: aba9efe5-7198-4bc9-b322-1e08987cf76d

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.045 sec. Processed 32.79 million rows, 689.60 MB (731.32 million rows/s., 15.38 GB/s.)
Peak memory usage: 15.64 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_1b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 8f3db064-fd92-47dc-bb4b-5e5d42a078f6

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.043 sec. Processed 32.79 million rows, 689.60 MB (759.44 million rows/s., 15.97 GB/s.)
Peak memory usage: 15.31 MiB.

```


### 1 billion raw data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 254,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          28202786
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          15992012
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          14390575
        ]
      }
    ]
  }
}

#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 254,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          28202786
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          15992012
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          14390575
        ]
      }
    ]
  }
}


#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 258,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          28202786
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          15992012
        ]
      },
      {
        "_index": "pypi_1b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          14390575
        ]
      }
    ]
  }
}

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

### 1 billion raw data set - pre-calculated `downloads per country per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
GET pypi_1b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 65,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          617810
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          562834
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          441337
        ]
      }
    ]
  }
}


#################################################
GET pypi_1b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 68,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          617810
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          562834
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          441337
        ]
      }
    ]
  }
}

#################################################
GET pypi_1b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 81,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          617810
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          562834
        ]
      },
      {
        "_index": "pypi_1b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          441337
        ]
      }
    ]
  }
}

```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: c5006844-5b5b-406d-b0ae-0e479d665a85

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.015 sec. Processed 57.34 thousand rows, 1.75 MB (3.94 million rows/s., 120.24 MB/s.)
Peak memory usage: 13.11 MiB.

------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 34c98664-20ee-4131-9d7a-ac8ed756eec1

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.017 sec. Processed 57.34 thousand rows, 1.75 MB (3.33 million rows/s., 101.52 MB/s.)
Peak memory usage: 13.11 MiB.
------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_1b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: c0c8a76d-e35d-4380-88cf-ebdddc5f05df

   ┌─project───────────┬──count─┐
1. │ cryptography      │ 617810 │
2. │ typing-extensions │ 562834 │
3. │ pyjwt             │ 441337 │
   └───────────────────┴────────┘

3 rows in set. Elapsed: 0.015 sec. Processed 57.34 thousand rows, 1.75 MB (3.91 million rows/s., 119.16 MB/s.)
Peak memory usage: 13.11 MiB.
```



### 10 billion raw data set - raw data - downloads per project

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 


```
#################################################

GET pypi-10b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 33773,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 86015065,
      "sum_other_doc_count": 9432931654,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 278873617
        },
        {
          "key": "urllib3",
          "doc_count": 158164615
        },
        {
          "key": "requests",
          "doc_count": 142282585
        }
      ]
    }
  }
}



#################################################

GET pypi-10b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 33326,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 86015065,
      "sum_other_doc_count": 9432931654,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 278873617
        },
        {
          "key": "urllib3",
          "doc_count": 158164615
        },
        {
          "key": "requests",
          "doc_count": 142282585
        }
      ]
    }
  }
}


#################################################

GET pypi-10b-ns-index_sorting/_search?request_cache=false
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

{
  "took": 33470,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "projects": {
      "doc_count_error_upper_bound": 86015065,
      "sum_other_doc_count": 9432931654,
      "buckets": [
        {
          "key": "boto3",
          "doc_count": 278873617
        },
        {
          "key": "urllib3",
          "doc_count": 158164615
        },
        {
          "key": "requests",
          "doc_count": 142282585
        }
      ]
    }
  }
}

```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
278873617      |boto3          
158164615      |urllib3        
142282585      |requests       

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [31457]ms


#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
278873617      |boto3          
158164615      |urllib3        
142282585      |requests       

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [30387]ms
 
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |    project    
---------------+---------------
278873617      |boto3          
158164615      |urllib3        
142282585      |requests 

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns-index_sorting 
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [34295]ms  

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

Query id: 93e8f96d-e500-4dd3-8fd2-24fba4baa35c

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 6.839 sec. Processed 10.01 billion rows, 188.61 GB (1.46 billion rows/s., 27.58 GB/s.)
Peak memory usage: 567.95 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: de6c5f4d-ef5a-4198-93f5-cdf366e94dc2

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 6.863 sec. Processed 10.01 billion rows, 188.61 GB (1.46 billion rows/s., 27.48 GB/s.)
Peak memory usage: 569.06 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: d762a041-2c53-4a29-bcac-3d1742856416

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 6.803 sec. Processed 10.01 billion rows, 188.61 GB (1.47 billion rows/s., 27.73 GB/s.)
Peak memory usage: 574.23 MiB.
```

### 10 billion raw data set - raw data - downloads per project for a specific country

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
GET pypi-10b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}

{
  "took": 1982,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 2405679,
      "sum_other_doc_count": 308182638,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 6108765
        },
        {
          "key": "typing-extensions",
          "doc_count": 5562752
        },
        {
          "key": "pyjwt",
          "doc_count": 4362553
        }
      ]
    }
  }
}


#################################################
GET pypi-10b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}

{
  "took": 1847,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 2405679,
      "sum_other_doc_count": 308182638,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 6108765
        },
        {
          "key": "typing-extensions",
          "doc_count": 5562752
        },
        {
          "key": "pyjwt",
          "doc_count": 4362553
        }
      ]
    }
  }
}



#################################################
GET pypi-10b-ns-index_sorting/_search?request_cache=false
{
  "size": 0,
  "query": {
    "term": {
      "country_code": "NL"
    }
  },
  "aggregations": {
    "countries": {
      "terms": {
        "field": "project",
        "size": 3
      }
    }
  }
}

{
  "took": 1832,
  "timed_out": false,
  "_shards": {
    "total": 48,
    "successful": 48,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": []
  },
  "aggregations": {
    "countries": {
      "doc_count_error_upper_bound": 2405679,
      "sum_other_doc_count": 308182638,
      "buckets": [
        {
          "key": "cryptography",
          "doc_count": 6108765
        },
        {
          "key": "typing-extensions",
          "doc_count": 5562752
        },
        {
          "key": "pyjwt",
          "doc_count": 4362553
        }
      ]
    }
  }
}



```
#### Elasticsearch - ESQL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |     project     
---------------+-----------------
6108765        |cryptography     
5562752        |typing-extensions
4362553        |pyjwt            

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [96158]ms


#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |     project     
---------------+-----------------
6108765        |cryptography     
5562752        |typing-extensions
4362553        |pyjwt            

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [95710]ms


#################################################
POST /_query?format=txt
{
  "query": """
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  """
}

     count     |     project     
---------------+-----------------
6108765        |cryptography     
5562752        |typing-extensions
4362553        |pyjwt            

Finished execution of ESQL query.
Query string: [
    FROM pypi-10b-ns
    | WHERE country_code == "NL"
    | STATS count = COUNT() BY project 
    | SORT count DESC 
    | LIMIT 3
  ]
Execution time: [95797]ms
```
#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 97160b9b-96e8-4816-a191-bc6b90bce1dc

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.273 sec. Processed 324.23 million rows, 6.82 GB (1.19 billion rows/s., 24.98 GB/s.)
Peak memory usage: 261.27 MiB.




------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_10b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 6b26f7b8-198e-418f-badf-ff6264da1f27

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.289 sec. Processed 324.23 million rows, 6.82 GB (1.12 billion rows/s., 23.63 GB/s.)
Peak memory usage: 261.27 MiB.

------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    count() AS count
FROM pypi_10b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: c3b12d6c-c836-409e-9ecb-75ec531fcabf

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.276 sec. Processed 324.23 million rows, 6.82 GB (1.18 billion rows/s., 24.73 GB/s.)
Peak memory usage: 261.27 MiB.

```


### 10 billion raw data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache 

```
#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}


{
  "took": 315,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          278873617
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          158164615
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          142282585
        ]
      }
    ]
  }
}


#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 318,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          278873617
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          158164615
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          142282585
        ]
      }
    ]
  }
}




#################################################
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
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}

{
  "took": 312,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_project",
        "_id": "Ym2v7vrgBfGHbIXoKBiYIQoAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "boto3"
          ]
        },
        "sort": [
          278873617
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "dZxJAQcMZDD0ErAB4qmqulAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "urllib3"
          ]
        },
        "sort": [
          158164615
        ]
      },
      {
        "_index": "pypi_10b_by_project",
        "_id": "chgGbKKTZg4TZe-Dpm7MUJAAAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "requests"
          ]
        },
        "sort": [
          142282585
        ]
      }
    ]
  }
}

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

Query id: b9c29ce3-c0f4-461c-905f-72e140f7a027

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.028 sec. Processed 465.98 thousand rows, 14.06 MB (16.47 million rows/s., 496.89 MB/s.)
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

Query id: 50053d32-c9a6-4293-a1f0-44019093b824

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.025 sec. Processed 465.98 thousand rows, 14.06 MB (18.50 million rows/s., 558.09 MB/s.)
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

Query id: 932cd62f-b347-47c3-9691-1f6fd0efa43e

   ┌─project──┬─────count─┐
1. │ boto3    │ 278873617 │
2. │ urllib3  │ 158164615 │
3. │ requests │ 142282585 │
   └──────────┴───────────┘

3 rows in set. Elapsed: 0.027 sec. Processed 465.98 thousand rows, 14.06 MB (17.29 million rows/s., 521.76 MB/s.)
Peak memory usage: 64.05 MiB.
```

### 10 billion raw data set - pre-calculated `downloads per country per project` 

#### Elasticsearch - Query DSL

Before each query run, we 
- manually dropped the request and query caches via the [clear cache API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-clearcache.html) 
- manually [dropped](./README.md#process-for-dropping-filesystem-cache-for-elasticsearch)  the filesystem cache

```
#################################################
GET pypi_10b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}


{
  "took": 148,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          6108765
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          5562752
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          4362553
        ]
      }
    ]
  }
}


#################################################
GET pypi_10b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}


{
  "took": 189,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          6108765
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          5562752
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          4362553
        ]
      }
    ]
  }
}

#################################################
GET pypi_10b_by_country_code_project/_search?request_cache=false
{
  "size": 3,
  "query": {
    "term": {
      "country_code_group": "NL"
    }
  },
  "sort": {
    "_script": {
      "type": "Number",
      "order": "desc",
      "script": {
        "lang": "painless",
        "source": """
          String s = doc['project.terms'].value;
          int int_value = Integer.parseInt(s);
          return int_value;
        """
      }
    }
  },
  "docvalue_fields": ["project_group"]
}


{
  "took": 151,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 10000,
      "relation": "gte"
    },
    "max_score": null,
    "hits": [
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TmNKfms74JVDZN0PrGH40s4AAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "cryptography"
          ]
        },
        "sort": [
          6108765
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnTuSbQMBDhFN3O1ZtdKIicFAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "typing-extensions"
          ]
        },
        "sort": [
          5562752
        ]
      },
      {
        "_index": "pypi_10b_by_country_code_project",
        "_id": "TnAhWLwU_ErYFfh6s3N9hxohAAAAAAAA",
        "_score": null,
        "fields": {
          "project_group": [
            "pyjwt"
          ]
        },
        "sort": [
          4362553
        ]
      }
    ]
  }
}

```

#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 787a190e-2d98-4fd9-aef6-dd3ecbba8cbe

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.037 sec. Processed 131.07 thousand rows, 4.02 MB (3.51 million rows/s., 107.63 MB/s.)
Peak memory usage: 18.22 MiB.

------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 2c97cd09-5e71-489b-8083-e3035d3737e5

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.036 sec. Processed 131.07 thousand rows, 4.02 MB (3.67 million rows/s., 112.52 MB/s.)
Peak memory usage: 18.22 MiB.
------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_10b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 83da24a7-8b7b-491d-9185-74f04eb59054

   ┌─project───────────┬───count─┐
1. │ cryptography      │ 6108765 │
2. │ typing-extensions │ 5562752 │
3. │ pyjwt             │ 4362553 │
   └───────────────────┴─────────┘

3 rows in set. Elapsed: 0.035 sec. Processed 131.07 thousand rows, 4.02 MB (3.73 million rows/s., 114.41 MB/s.)
Peak memory usage: 18.22 MiB.
```



### 100 billion raw data set - raw data - downloads per project


#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 5aaa64bf-7cd6-4025-b094-e76fbf6b6383

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 82.528 sec. Processed 110.21 billion rows, 2.08 TB (1.34 billion rows/s., 25.15 GB/s.)
Peak memory usage: 1.31 GiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 6fafccd0-040d-4b09-9816-373ffef29e5c

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 84.402 sec. Processed 110.21 billion rows, 2.08 TB (1.31 billion rows/s., 24.60 GB/s.)
Peak memory usage: 1.31 GiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 4264225e-6790-4c61-b237-f38ecf3b3dc3

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 83.392 sec. Processed 110.21 billion rows, 2.08 TB (1.32 billion rows/s., 24.89 GB/s.)
Peak memory usage: 1.30 GiB.
```

### 100 billion raw data set - raw data - downloads per project for a specific country


#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: ce39f83e-ed8d-4150-805a-414c6f32854b

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 2.981 sec. Processed 3.51 billion rows, 73.60 GB (1.18 billion rows/s., 24.69 GB/s.)
Peak memory usage: 275.83 MiB.




------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 4e51a17f-0f8e-4e1f-b48e-1fdb411c4925

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 2.861 sec. Processed 3.51 billion rows, 73.60 GB (1.23 billion rows/s., 25.72 GB/s.)
Peak memory usage: 275.71 MiB.
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    count() AS count
FROM pypi_100b
WHERE country_code = 'NL'
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 6c99087d-1b4b-40ef-a321-d3da4b065f0d

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 2.924 sec. Processed 3.51 billion rows, 73.60 GB (1.20 billion rows/s., 25.17 GB/s.)
Peak memory usage: 276.51 MiB.

```


### 100 billion raw data set -  pre-calculated `downloads per project` 


#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 5ea8d0d1-0a7a-4819-ab10-d7b8b27754f6

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 0.037 sec. Processed 1.33 million rows, 40.05 MB (35.72 million rows/s., 1.07 GB/s.)
Peak memory usage: 168.17 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: c3257e67-7e44-4d00-a9cb-b224344adc53

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 0.034 sec. Processed 1.33 million rows, 40.05 MB (38.94 million rows/s., 1.17 GB/s.)
Peak memory usage: 168.17 MiB.

------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_project
GROUP BY project
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: 8063f4b1-16ca-48ac-8905-8c3b46d5bd7d

   ┌─project──┬──────count─┐
1. │ boto3    │ 3170361994 │
2. │ urllib3  │ 1710686069 │
3. │ botocore │ 1564265238 │
   └──────────┴────────────┘

3 rows in set. Elapsed: 0.038 sec. Processed 1.33 million rows, 40.05 MB (35.29 million rows/s., 1.06 GB/s.)
Peak memory usage: 160.13 MiB.
```

### 100 billion raw data set - pre-calculated `downloads per country per project` 



#### ClickHouse - SQL
```
------------------------------------------------------------------------------------------------------------------------
SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: cff6719d-a4e6-4581-bfc3-b19f95d82d23

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 0.047 sec. Processed 671.74 thousand rows, 20.57 MB (14.21 million rows/s., 435.06 MB/s.)
Peak memory usage: 111.84 MiB.

------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: f3a7ae29-f596-4ec0-a481-dbad695d2b81

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 0.044 sec. Processed 671.74 thousand rows, 20.57 MB (15.11 million rows/s., 462.70 MB/s.)
Peak memory usage: 103.63 MiB.
------------------------------------------------------------------------------------------------------------------------

SELECT
    project,
    sum(count) AS count
FROM pypi_100b_by_country_code_project
WHERE country_code = 'NL'
GROUP BY
    project,
    country_code
ORDER BY count DESC
LIMIT 3
SETTINGS max_threads = 32, enable_filesystem_cache = 0, use_query_cache = 0

Query id: da27f5c7-3888-4d9a-9e05-a7e6ef302ca0

   ┌─project───────────┬────count─┐
1. │ typing-extensions │ 61390649 │
2. │ cryptography      │ 57540814 │
3. │ pyjwt             │ 48165070 │
   └───────────────────┴──────────┘

3 rows in set. Elapsed: 0.046 sec. Processed 671.74 thousand rows, 20.57 MB (14.70 million rows/s., 450.34 MB/s.)
Peak memory usage: 119.92 MiB.
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
CREATE OR REPLACE TABLE pypi_10b_by_country_code_project_backfilled
(
    `country_code` LowCardinality(String),
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (country_code, project);
```

```
INSERT INTO pypi_10b_by_country_code_project_backfilled
SELECT
    country_code,
    project,
    count() AS count
FROM pypi_10b
GROUP BY country_code, project
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
CREATE OR REPLACE TABLE pypi_10b_by_country_code_project_backfilled
(
    `country_code` LowCardinality(String),
    `project` String,
    `count` SimpleAggregateFunction(sum, Int64)
)
ENGINE = AggregatingMergeTree
ORDER BY (country_code, project);
```

```
CREATE MATERIALIZED VIEW pypi_10b_by_country_code_project_mv_backfilled TO pypi_10b_by_country_code_project_backfilled AS
SELECT
    country_code,
    project,
    count() AS count
FROM pypi_10b_null
GROUP BY country_code, project;
```
```
INSERT INTO pypi_10b_null
SELECT * FROM pypi_10b
SETTINGS
    max_threads = 30,
    max_insert_threads = 30;
```


### ClickHouse PyPi table without LowCardinality type

#### DDL
```
CREATE OR REPLACE TABLE pypi_1b_strings_only
(
    `timestamp` DateTime,
    `country_code` String,
    `url` String,
    `project` String
)
ORDER BY (country_code, project, url, timestamp);
```

#### Load data
```
INSERT INTO pypi_1b_strings_only
SELECT * FROM pypi_1b
SETTINGS
    max_threads=32,
    max_insert_threads=32;
```

#### Check sizes
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableQuantity(count()) AS parts,
    formatReadableSize(sum(data_uncompressed_bytes)) AS data_size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS data_size_compressed,
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk
FROM system.parts
WHERE active AND (database = 'default') AND ((`table` = 'pypi_1b_strings_only') OR (`table` = 'pypi_1b'))
GROUP BY `table`
ORDER BY `table` ASC

Query id: 31b057a6-1ea7-462f-afab-f16b03cd78fd

   ┌─table────────────────┬─rows─────────┬─parts─┬─data_size_uncompressed─┬─data_size_compressed─┬─total_size_on_disk─┐
1. │ pypi_1b              │ 1.01 billion │ 1.00  │ 126.63 GiB             │ 5.24 GiB             │ 5.24 GiB           │
2. │ pypi_1b_strings_only │ 1.01 billion │ 1.00  │ 128.52 GiB             │ 5.24 GiB             │ 5.25 GiB           │
   └──────────────────────┴──────────────┴───────┴────────────────────────┴──────────────────────┴────────────────────┘
```