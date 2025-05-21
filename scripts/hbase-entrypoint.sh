#!/bin/bash

set -e

HBASE_ROLE=${HBASE_ROLE:-regionserver}

# Create HBase directory if it doesn't exist
hdfs dfs -mkdir -p /hbase || sleep 5
hdfs dfs -chown hadoop:hadoop /hbase || sleep 5

case "$HBASE_ROLE" in
  "hmaster")
    echo "Starting HBase Master"
    exec hbase master start
    ;;
  "regionserver")
    echo "Starting RegionServer"
    hdfs --daemon start datanode
    yarn --daemon start nodemanager
    exec hbase regionserver start
    ;;
  *)
    echo "Invalid HBASE_ROLE: $HBASE_ROLE" >&2
    exit 1
    ;;
esac