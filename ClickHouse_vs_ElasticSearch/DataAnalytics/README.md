# ClickHouse vs Elasticsearch for Real-time Analytics

These tests were performed on ClickHouse 24.4 and Elasticsearch 8.12.2.

## Goals

To provide a real-time analytics benchmark comparing ClickHouse and Elasticsearch when resources are comparable and all effort is made to optimize both.

## Use case and dataset 



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
    enable_filesystem_cache=0;
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
    enable_filesystem_cache=0;
```

#### Elasticsearch query DSL
```
# default sort size is by number of docs in decending order
#GET pypi-100b-ns/_search?request_cache=false
#GET pypi-10b-ns/_search?request_cache=false
GET pypi-1b-ns/_search?request_cache=false
{
  "size": 0,
  "query": { "term": { "project": "boto3" } },
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
    enable_filesystem_cache=0;
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
    enable_filesystem_cache=0;
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


## Storage sizes

### 1 billion row data set - raw data

#### Elasticsearch - LZ4 compression, with _source
```
GET _data_stream/pypi-1b-s/_stats?human=true

{
  "_shards": {
    "total": 20,
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
```
#### Elasticsearch - LZ4 compression, without _source
```
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











## Query runtimes

### 1 billion row data set - raw data

#### Elasticsearch - Query DSL
```
TODO
```
#### Elasticsearch - ESQL
```
TODO
```
#### ClickHouse - SQL
```
TODO
```


### 1 billion row data set -  pre-calculated `downloads per project` 

#### Elasticsearch - Query DSL
```
TODO
```
#### Elasticsearch - ESQL
```
TODO
```
#### ClickHouse - SQL
```
TODO
```

### 1 billion row data set -  pre-calculated `downloads per project per country` 

#### Elasticsearch - Query DSL
```
TODO
```
#### Elasticsearch - ESQL
```
TODO
```
#### ClickHouse - SQL
```
TODO
```



