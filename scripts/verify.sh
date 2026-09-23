#!/bin/bash

set -e

echo "=== Swarm Nodes ==="
docker node ls

echo ""
echo "=== Services ==="
docker service ls

echo ""
echo "=== Elasticsearch ==="
docker service ps elk_elasticsearch

echo ""
echo "=== Kibana ==="
docker service ps elk_kibana

echo ""
echo "=== Logstash ==="
docker service ps elk_logstash

echo ""
echo "=== Elasticsearch API ==="
curl -s http://192.168.198.144:9200

echo ""
echo ""
echo "Verification completed."