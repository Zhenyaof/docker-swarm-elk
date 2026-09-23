#!/bin/bash

set -e

echo "Creating ELK overlay network..."
docker network inspect elk_net >/dev/null 2>&1 || \
docker network create --driver overlay --attachable elk_net

echo "Deploying Elasticsearch..."
docker stack deploy -c 01-elasticsearch.yml elk

echo "Deploying Kibana..."
docker stack deploy -c 02-kibana.yml elk

echo "Deploying Logstash..."
docker stack deploy -c 03-logstash.yml elk

echo "Deployment completed."

docker service ls