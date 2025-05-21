#!/bin/bash

# Determine if this is a master or worker node
ROLE=${ROLE:-worker}
CLUSTER_ID=${CLUSTER_ID:-hadoop-cluster}
HOSTNAME=$(hostname)


# Function to start ZooKeeper server
start_zookeeper() {
    # Ensure proper permissions
    sudo chown -R hadoop:hadoop $ZOOKEEPER_HOME/data
    sudo chmod -R 755 $ZOOKEEPER_HOME/data
    
    # Create myid file with proper permissions
    if [[ "$ROLE" == "master" ]]; then
        echo "$ZK_ID" > $ZOOKEEPER_HOME/data/myid
        sudo chown hadoop:hadoop $ZOOKEEPER_HOME/data/myid
        sudo chmod 644 $ZOOKEEPER_HOME/data/myid
        echo "ZooKeeper myid set to $ZK_ID"
    fi
    
    $ZOOKEEPER_HOME/bin/zkServer.sh start
}

start_journalnode() {
    hdfs --daemon start journalnode
}

# Check if NameNode is already formatted
is_namenode_formatted() {
    [ -d /hadoopdata/namenode/current ]
}

initialize_first_namenode() {
    if ! is_namenode_formatted; then
        echo "Formatting NameNode..."
        hdfs namenode -format -clusterId $CLUSTER_ID -force
        hdfs namenode -initializeSharedEdits -force

        # Wait longer for ZooKeeper to be fully ready
        echo "Waiting for ZooKeeper to stabilize..."
        sleep 10
        hdfs zkfc -formatZK -force
        sleep 10
    
    else
        echo "NameNode already formatted, skipping format step"
    fi
    
    
    
    # Start services
    hdfs --daemon start namenode
    hdfs --daemon start zkfc
}

bootstrap_standby_namenode() {
    if ! is_namenode_formatted; then
        echo "Bootstrapping standby NameNode..."
        echo "Y" | hdfs namenode -bootstrapStandby -force

        if [ $? -ne 0 ]; then
            echo "ERROR: Bootstrap failed. Retrying after 30 seconds..."
            sleep 30
            echo "Y" | hdfs namenode -bootstrapStandby -force
        fi
        
        hdfs --daemon start namenode
        hdfs --daemon start zkfc
    else
        echo "Standby NameNode already bootstrapped, skipping bootstrap step"
        hdfs --daemon start namenode
        hdfs --daemon start zkfc
    fi
}

start_resourcemanager() {
    yarn --daemon start resourcemanager
}

start_datanode() {
    hdfs --daemon start datanode
}

start_nodemanager() {
    yarn --daemon start nodemanager
}

wait_for_zookeeper() {
    echo "Waiting for ZooKeeper to be ready..."
    until nc -z master1 2181 && nc -z master2 2181 && nc -z master3 2181; do
        sleep 2
    done
    echo "ZooKeeper is ready"
}

wait_for_journalnodes() {
    echo "Waiting for JournalNodes to be ready..."
    until nc -z master1 8485 && nc -z master2 8485 && nc -z master3 8485; do
        sleep 2
    done
    echo "JournalNodes are ready"
}

wait_for_namenode() {
    echo "Waiting for NameNode to be ready..."
    until nc -z master1 8020; do
        sleep 1
    done
    echo "NameNode is ready"
}

# Create ZooKeeper myid file for masters
if [[ "$ROLE" == "master" ]]; then
    start_zookeeper
    start_journalnode

    wait_for_zookeeper
    
    if [[ "$ZK_ID" == "1" ]]; then
        initialize_first_namenode
        wait_for_journalnodes
    else
        wait_for_namenode
        bootstrap_standby_namenode
    fi
    
    start_resourcemanager
else
    wait_for_namenode
    start_datanode
    start_nodemanager
fi

# For master nodes only
if [[ "$ROLE" == "master" ]]; then
    # Wait for HDFS to be healthy
    until hdfs dfsadmin -report; do
        echo "Waiting for HDFS to be ready..."
        sleep 5
    done
    
fi

# Keep the container running
tail -f /dev/null