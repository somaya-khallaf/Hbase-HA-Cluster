# HBase WebTable Case Study

## Overview

This project demonstrates the design and implementation of a highly scalable, efficient web page storage system using Apache HBase.



## Prerequisites and Setup

### Required Software
* Apache HBase (latest stable version)
* Python 3.x
* pip3 (Python package manager)

### Installation Steps

1. Install Python and pip:
```bash
sudo apt install -y python3 python3-pip
```

2. Install required Python packages:
```bash
sudo pip3 install happybase faker
```

3. Start HBase Thrift server:
```bash
hbase-daemon.sh start thrift
```

### Environment Setup
* Ensure HBase is running and accessible
* Verify the Thrift server is running on the default port (9090)
* Make sure you have appropriate permissions to create and modify HBase tables



## Business Requirements

Your company operates a large-scale web content platform and requires the ability to:

* Store HTML content, metadata, and link structures of web pages
* Retrieve and filter pages based on metadata (e.g., status codes, domains)
* Support time-based queries and pagination for audits and analytics
* Optimize storage performance with TTLs and versioning policies



## HBase Table Design

### Table Name
```bash
web_pages
```

### Column Families

| Family   | Purpose                | Versions | TTL (sec) | Bloom Filter | Block Size | Block Cache |
| -------- | ---------------------- | -------- | --------- | ------------ | ---------- | ----------- |
| content  | Stores HTML content    | 3        | 90 days   | ROWCOL       | 64 KB      | Yes         |
| metadata | Page metadata in JSON  | 1        | None      | ROWCOL       | 64 KB      | Yes         |
| outlinks | Outbound links in JSON | 2        | 180 days  | ROWCOL       | 64 KB      | No          |
| inlinks  | Inbound links in JSON  | 2        | 180 days  | ROWCOL       | 64 KB      | No          |

### Table Properties Explanation

#### Column Family Properties

1. **VERSIONS**
   * **Purpose**: Controls how many versions of each cell to keep
   * **Importance**: 
     * Content: 3 versions allow tracking content changes over time
     * Metadata: 1 version since metadata updates replace old values
     * Links: 2 versions to track link changes while limiting storage

2. **TTL (Time To Live)**
   * **Purpose**: Automatically deletes data after specified seconds
   * **Importance**:
     * Content: 90 days (7776000s) balances freshness with history
     * Links: 180 days (15552000s) longer retention for link analysis
     * Metadata: No TTL to maintain historical records

3. **BLOOMFILTER**
   * **Purpose**: Memory-efficient data structure to check if a row/column exists
   * **Importance**:
     * ROWCOL type improves read performance
     * Reduces disk I/O for non-existent data

4. **BLOCKSIZE**
   * **Purpose**: Size of data blocks stored in HFiles
   * **Importance**:
     * 64KB (65536 bytes) balances read performance
     * Optimized for typical web page sizes

5. **BLOCKCACHE**
   * **Purpose**: Caches frequently accessed data in memory
   * **Importance**:
     * Enabled for content and metadata (frequent reads)
     * Disabled for links (less frequent access)
     * Improves read performance for hot data

#### Table Properties

1. **SPLITS**
   * **Purpose**: Pre-splits table into regions
   * **Importance**:
     * Prevents region server hotspots
     * Enables parallel processing
     * Improves write and read performance

### Row Key Design

```
<salt>|<domain>|<timestamp>|<url_hash>
```

* **Salt**: MD5-based value (0-9) for pre-split region distribution and hotspot prevention
* **Domain**: Logical grouping for filtering
* **Timestamp**: Enables time-based scans and sorting
* **URL Hash**: Ensures uniqueness and compact format

#### Rationale

* **Strengths**:
  * Enables even load distribution across regions
  * Allows domain-specific filtering using PrefixFilter
  * Supports time-range scans due to embedded timestamp

* **Weaknesses**:
  * Cannot query efficiently by URL only (need full row key)



## Implementation Guide

### 1. Create the HBase Table
```bash
hbase shell
create 'web_pages', \
  {NAME => 'content', VERSIONS => 3, TTL => 7776000, BLOOMFILTER => 'ROWCOL', BLOCKSIZE => 65536, BLOCKCACHE => true}, \
  {NAME => 'metadata', VERSIONS => 1, BLOOMFILTER => 'ROWCOL', BLOCKSIZE => 65536, BLOCKCACHE => true}, \
  {NAME => 'outlinks', VERSIONS => 2, TTL => 15552000, BLOOMFILTER => 'ROWCOL', BLOCKSIZE => 65536}, \
  {NAME => 'inlinks', VERSIONS => 2, TTL => 15552000, BLOOMFILTER => 'ROWCOL', BLOCKSIZE => 65536}, \
  SPLITS => ['1', '2', '3', '4', '5', '6', '7', '8', '9']
```

### 2. Generate Sample Data
```bash
python3 /code/generate_web_data.py
```

### 3. Query Operations

#### Basic Operations
```bash
# Insert
put 'web_pages', '0|example.com|1682000000|abc12345', 'content:html', '<html>...</html>'
put 'web_pages', '0|example.com|1682000000|abc12345', 'metadata:json', '{...}'

# Retrieve
get 'web_pages', '0|example.com|1682000000|abc12345'

# Update
put 'web_pages', '0|example.com|1682000000|abc12345', 'content:html', '<html>updated</html>'

# Delete
deleteall 'web_pages', '0|example.com|1682000000|abc12345'
```

#### Advanced Queries
```bash
# Pages with title containing 'sample'
scan 'web_pages', {FILTER => "SingleColumnValueFilter('metadata', 'json', =, 'substring:sample')"}

# Pages with 404 status
scan 'web_pages', {FILTER => "SingleColumnValueFilter('metadata', 'json', =, 'substring:404')"}

# Verify data
count 'web_pages'
scan 'web_pages', {LIMIT => 5}
```