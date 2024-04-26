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
PUT _data_stream/pypi-1b00-s-index_sorting-best_compression
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
PUT pypi_1b_by_country_code_project
PUT pypi_1b_by_country_code_project
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
    "index": "pypi_1b_by_project"
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

#### Elasticsearch

##### With `_source`, No index sorting, `LZ4` codec
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
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b')
GROUP BY `table`
ORDER BY `table` ASC

Query id: f2a55c56-b521-4360-8ca0-3a373372874a

   ┌─table───┬─rows─────────┬─size_uncompressed─┬─size_compressed─┐
1. │ pypi_1b │ 1.01 billion │ 126.63 GiB        │ 5.24 GiB        │
   └─────────┴──────────────┴───────────────────┴─────────────────┘
```
#### ClickHouse
##### ZSTD compression
```
SELECT
    `table`,
    formatReadableQuantity(sum(rows)) AS rows,
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_zstd')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 73795d4f-52eb-4239-a054-94c31d132af3

   ┌─table────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┐
1. │ pypi_1b_zstd │ 1.01 billion │ 126.63 GiB        │ 3.45 GiB        │
   └──────────────┴──────────────┴───────────────────┴─────────────────┘
```

### 1 billion row data set -  pre-calculated `downloads per project` 

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
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 47597e25-552a-4977-8942-d3dcae9bddcf

   ┌─table──────────────┬─rows────────────┬─size_uncompressed─┬─size_compressed─┐
1. │ pypi_1b_by_project │ 434.78 thousand │ 9.17 MiB          │ 4.94 MiB        │
   └────────────────────┴─────────────────┴───────────────────┴─────────────────┘
```


### 1 billion row data set -  pre-calculated `downloads per country per project` 

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
    formatReadableSize(sum(data_uncompressed_bytes)) AS size_uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS size_compressed
FROM system.parts
WHERE active AND (database = 'default') AND (`table` = 'pypi_1b_by_country_code_project')
GROUP BY `table`
ORDER BY `table` ASC

Query id: 67977a9f-a640-4f54-99f7-5adbfcbc2e72

   ┌─table───────────────────────────┬─rows─────────┬─size_uncompressed─┬─size_compressed─┐
1. │ pypi_1b_by_country_code_project │ 3.52 million │ 76.02 MiB         │ 38.27 MiB       │
   └─────────────────────────────────┴──────────────┴───────────────────┴─────────────────┘
```






## Query runtimes

### 1 billion row data set - raw data - downloads per project

#### Elasticsearch - Query DSL

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
#### Elasticsearch - ESQL

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

### 1 billion row data set - raw data - downloads per project for a specific country

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


### 1 billion row data set -  pre-calculated `downloads per project` 

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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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

### 1 billion row data set - pre-calculated `downloads per country per project` 

#### Elasticsearch - Query DSL
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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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
          int idvalue = Integer.parseInt(s);
          return idvalue;
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


