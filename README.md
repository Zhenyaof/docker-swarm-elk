# Docker Swarm ELK Stack

A three-node Docker Swarm deployment running Elasticsearch, Kibana, and Logstash with persistent storage, node-specific placement, an isolated overlay network, and service health verification.

## Architecture

| Node | IP Address | Role | Services |
|---|---|---|---|
| Manager | 192.168.198.140 | Manager | Logstash |
| Worker1 | 192.168.198.139 | Worker | Kibana + Logstash |
| Worker3 | 192.168.198.144 | Worker | Elasticsearch + Logstash |

Worker2 (192.168.198.138) was initially used for Elasticsearch and was later drained and removed from the Swarm. Elasticsearch was migrated to Worker3 before Worker2 was removed.

### Final ELK placement

- Elasticsearch: Worker3
- Kibana: Worker1
- Logstash: Manager + Worker1 + Worker3
- Worker3: replacement for Worker2
- `elk_net`: dedicated overlay network
## Technologies

- Docker Engine
- Docker Swarm
- Elasticsearch 8.15.3
- Kibana 8.15.3
- Logstash 8.15.3
- Ubuntu
- CentOS Stream 9
- Docker Overlay Networking
- Persistent Host Volumes

## Project Structure

    docker-swarm-elk/
    ├── README.md
    ├── 01-elasticsearch.yml
    ├── 02-kibana.yml
    ├── 03-logstash.yml
    ├── logstash/
    │   └── pipeline/
    │       └── logstash.conf
    ├── scripts/
    │   ├── deploy.sh
    │   └── verify.sh
    └── docs/
        └── architecture.md

## 1. Initialize Docker Swarm

Run this command on the Manager node:

    docker swarm init --advertise-addr 192.168.198.140

The command returns a worker join command similar to:

    docker swarm join --token <TOKEN> 192.168.198.140:2377

Run the generated join command on Worker1 and Worker2.

After adding the workers, verify the cluster:

    docker node ls

## 2. Add Worker3

Join the new server to the Swarm using the worker join command:

    docker swarm join --token <TOKEN> 192.168.198.140:2377

Verify:

    docker node ls

Label the workers so services can be placed on specific nodes:

    docker node update --label-add role=worker1 <WORKER1_NODE_ID>

    docker node update --label-add role=worker2 <WORKER2_NODE_ID>

    docker node update --label-add role=worker3 <WORKER3_NODE_ID>

Verify labels:

    docker node inspect <NODE_ID> --format '{{ .Spec.Labels }}'

## 3. Create the ELK Overlay Network

Create a dedicated overlay network from the Manager:

    docker network create \
      --driver overlay \
      --attachable \
      elk_net

Verify:

    docker network ls

The ELK services use only this dedicated network.

## 4. Persistent Storage

Create persistent directories on the Linux nodes:

    sudo mkdir -p /opt/elk/elasticsearch
    sudo mkdir -p /opt/elk/kibana
    sudo mkdir -p /opt/elk/logstash

For Elasticsearch:

    sudo chown -R 1000:0 /opt/elk/elasticsearch

For Kibana:

    sudo chown -R 1000:0 /opt/elk/kibana

For Logstash:

    sudo chown -R 1000:0 /opt/elk/logstash

The host directories are mounted into the containers so data survives container restarts.

## 5. Elasticsearch

Elasticsearch uses:

- Elasticsearch 8.15.3
- Single-node mode
- Persistent data
- Dedicated ELK overlay network
- Node placement constraint

Initial placement:

    node.labels.role == worker2

Configuration file:

    01-elasticsearch.yml

Important configuration:

    discovery.type=single-node
    xpack.security.enabled=false
    ES_JAVA_OPTS=-Xms512m -Xmx512m

Persistent volume:

    /opt/elk/elasticsearch:/usr/share/elasticsearch/data

Verify Elasticsearch:

    curl http://192.168.198.138:9200

After migration to Worker3:

    curl http://192.168.198.144:9200

A successful response returns Elasticsearch information including the version and cluster name.

## 6. Kibana

Kibana runs only on Worker1.

Configuration file:

    02-kibana.yml

Placement constraint:

    node.labels.role == worker1

Persistent volume:

    /opt/elk/kibana:/usr/share/kibana/data

Kibana connects to Elasticsearch using:

    ELASTICSEARCH_HOSTS=http://192.168.198.144:9200

Access Kibana from a browser:

    http://192.168.198.139:5601

## 7. Logstash

Logstash runs globally across the Swarm.

This means one Logstash task runs on each available Swarm node.

Configuration file:

    03-logstash.yml

Deployment mode:

    mode: global

Persistent volume:

    /opt/elk/logstash:/usr/share/logstash/data

Pipeline configuration:

    logstash/pipeline/logstash.conf

The pipeline uses a heartbeat input to continuously generate test events:

    input {
      heartbeat {
        interval => 60
        type => "swarm_test"
      }
    }

The events are sent to Elasticsearch using:

    hosts => ["http://elasticsearch:9200"]

The Elasticsearch index is:

    logstash-swarm-YYYY.MM.dd

## 8. Service Deployment

The ELK services can be deployed from the Manager.

Deploy Elasticsearch:

    docker stack deploy -c 01-elasticsearch.yml elk

Deploy Kibana:

    docker stack deploy -c 02-kibana.yml elk

Deploy Logstash:

    docker stack deploy -c 03-logstash.yml elk

Check services:

    docker service ls

Check Elasticsearch:

    docker service ps elk_elasticsearch

Check Kibana:

    docker service ps elk_kibana

Check Logstash:

    docker service ps elk_logstash

## 9. Service Health and Startup Order

The intended service dependency is:

    Elasticsearch
          |
          v
       Kibana
          |
          v
       Logstash

Elasticsearch must be available before Kibana connects to it.

After Elasticsearch and Kibana are operational, Logstash sends events to Elasticsearch.

Docker Swarm does not provide the same `depends_on` startup semantics as Docker Compose, so service health is verified through the application endpoints and service status.

Elasticsearch health can be checked with:

    curl http://192.168.198.144:9200

Kibana can be checked through:

    http://192.168.198.139:5601

Swarm service state can be checked with:

    docker service ls

## 10. Elasticsearch Migration from Worker2 to Worker3

The Elasticsearch data was copied from Worker2 to Worker3 before changing the placement constraint.

Create the archive on Worker2:

    sudo tar -czf /tmp/elasticsearch-data.tar.gz -C /opt/elk elasticsearch

Copy it to Worker3:

    scp /tmp/elasticsearch-data.tar.gz amir3@192.168.198.144:/tmp/

Extract on Worker3:

    sudo mkdir -p /opt/elk/elasticsearch

    sudo tar -xzf /tmp/elasticsearch-data.tar.gz -C /opt/elk

Set ownership:

    sudo chown -R 1000:0 /opt/elk/elasticsearch

Because Worker3 may not have internet access, the Elasticsearch image can also be transferred manually.

Save the image on Worker2:

    sudo docker save docker.elastic.co/elasticsearch/elasticsearch:8.15.3 | gzip > /tmp/elasticsearch-image.tar.gz

Copy the image:

    scp /tmp/elasticsearch-image.tar.gz amir3@192.168.198.144:/tmp/

Load it on Worker3:

    sudo docker load < /tmp/elasticsearch-image.tar.gz

Update the Elasticsearch placement:

    docker service update \
      --constraint-rm "node.labels.role == worker2" \
      --constraint-add "node.labels.role == worker3" \
      elk_elasticsearch

Verify:

    docker service ps elk_elasticsearch

Then verify Elasticsearch from Worker3:

    curl http://192.168.198.144:9200

## 11. Removing Worker2

Before removing Worker2, drain it so Swarm attempts to move its services to another suitable node:

    docker node update --availability drain <WORKER2_NODE_ID>

Verify:

    docker node ls

Check the Elasticsearch service:

    docker service ps elk_elasticsearch

After confirming that required services have successfully moved to Worker3, remove Worker2 from the Swarm from the Manager:

    docker node rm <WORKER2_NODE_ID>

If the node still has an active membership, run the following on Worker2:

    docker swarm leave

Then verify the remaining cluster:

    docker node ls

The final cluster should contain:

    Manager
    Worker1
    Worker3

## 12. Verification

Check all nodes:

    docker node ls

Check all services:

    docker service ls

Check Elasticsearch:

    docker service ps elk_elasticsearch

Check Kibana:

    docker service ps elk_kibana

Check Logstash:

    docker service ps elk_logstash

Check Elasticsearch directly:

    curl http://192.168.198.144:9200

Check Kibana:

    http://192.168.198.139:5601

Check Logstash logs:

    docker service logs elk_logstash

## 13. Expected Final Architecture

    ┌──────────────────────────────────────────────┐
    │              Docker Swarm Cluster            │
    │                                              │
    │  Manager                                     │
    │  192.168.198.140                             │
    │      │                                       │
    │      ├── Logstash                            │
    │      │                                       │
    │      ├──────────────────────────────┐        │
    │      │                              │        │
    │  Worker1                        Worker3      │
    │  192.168.198.139               192.168.198.144
    │      │                              │        │
    │      ├── Kibana                     ├── Elasticsearch
    │      └── Logstash                    └── Logstash
    │                                              │
    │                 elk_net                      │
    └──────────────────────────────────────────────┘

## 14. Useful Commands

List nodes:

    docker node ls

List services:

    docker service ls

Inspect a service:

    docker service inspect <SERVICE_NAME>

View service tasks:

    docker service ps <SERVICE_NAME>

View service logs:

    docker service logs <SERVICE_NAME>

Inspect the network:

    docker network inspect elk_net

Scale a service:

    docker service scale <SERVICE_NAME>=1

Drain a node:

    docker node update --availability drain <NODE_ID>

Activate a node:

    docker node update --availability active <NODE_ID>

## 15. Project Goal

This project demonstrates:

- Docker Swarm cluster management
- Manager and worker node configuration
- Node labels and placement constraints
- Docker overlay networking
- Persistent container storage
- Elasticsearch deployment
- Kibana deployment
- Logstash deployment
- Global Swarm services
- Service verification
- Data migration between Swarm nodes
- Worker node replacement and removal
- Basic ELK stack operation in a distributed environment

## Author

Amir Fakerov

GitHub:

https://github.com/Zhenyaof/docker-swarm-elk