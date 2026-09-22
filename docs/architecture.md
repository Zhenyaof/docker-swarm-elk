# Architecture

## Swarm Nodes

| Node | Role | IP Address | Service |
|---|---|---|---|
| Manager | Manager | 192.168.198.140 | Logstash |
| Worker1 | Worker | 192.168.198.139 | Kibana + Logstash |
| Worker2 | Worker | 192.168.198.138 | Logstash |
| Worker3 | Worker | 192.168.198.144 | Elasticsearch + Logstash |

## ELK Services

### Elasticsearch
- Runs only on Worker3.
- Persistent data is stored in `/opt/elk/elasticsearch`.
- Port `9200` is published in host mode.

### Kibana
- Runs only on Worker1.
- Persistent data is stored in `/opt/elk/kibana`.
- Port `5601` is exposed.
- Connects to Elasticsearch on Worker3.

### Logstash
- Runs as a global Swarm service.
- Runs on every active Swarm node.
- Persistent data is stored in `/opt/elk/logstash`.

## Network

All ELK services use the external Docker overlay network:

`elk_net`

The network is separate from the default application networks.

## Migration

Worker3 was added to the Swarm after the initial deployment.

Elasticsearch data was migrated from Worker2 to Worker3 before changing the Elasticsearch placement constraint.

Worker2 was then planned for removal from the Swarm after the services running on it were migrated or rescheduled.