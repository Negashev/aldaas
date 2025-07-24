# Aldaas API Documentation

## Overview

Aldaas (**A**pp with **L**arge **D**ata **a**s **a** **S**ervice) provides temporary database instances from production backups using Kubernetes, Argo Workflows, and Rook-Ceph storage snapshots.

## Core Components

### 1. Tunnel Service (`tunnel/aldaas.sh`)

The tunnel service creates a WebSocket-based proxy to database instances.

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ALDAAS_PROTOCOL` | `wss` | WebSocket protocol (ws/wss) |
| `ALDAAS_SERVER` | `$ARGO_SERVER` | Aldaas server hostname |
| `ALDAAS_PORT` | `5432` | Database port to proxy |
| `ALDAAS_TTL` | `300` | Time-to-live for database instance (seconds) |
| `ALDAAS_NAME` | - | Workflow template name |
| `ALDAAS_TOKEN` | - | Authentication token |

#### Usage Example

```bash
docker run -it \
  -p 5432:5432 \
  -e ALDAAS_PORT=5432 \
  -e ALDAAS_NAME=my-aldaas \
  -e ALDAAS_TOKEN=your-token \
  -e ARGO_SERVER=argo.example.com \
  -e ARGO_HTTP1=true \
  -e ARGO_TOKEN='your-argo-token' \
  -e ARGO_NAMESPACE=aldaas \
  ghcr.io/negashev/aldaas:main
```

### 2. Helm Chart Configuration

The Helm chart provides the complete Kubernetes deployment for Aldaas.

#### Core Values (`chart/values.yaml`)

##### Service Account
```yaml
serviceAccountName: argo-workflow  # SA from argo with RBAC permissions
```

##### Tunnel Configuration
```yaml
tunnel:
  image: ghcr.io/negashev/aldaas
  tag: main
  port: 8080                    # WebSocket tunnel port
  token: "your-secret-token"    # Authentication token
  ingress:
    tlsSecretName: ""           # TLS certificate secret
    annotations: {}             # Ingress annotations
```

##### Storage Configuration
```yaml
rook:
  storageClassName: ceph-block           # Rook-Ceph storage class
  volumeSnapshotClassName: ceph-block    # Volume snapshot class
```

##### S3 Backup Source
```yaml
s3:
  existingSecret: ""          # Existing K8s secret for S3 credentials
  accesskey: ""               # S3 access key
  secretkey: ""               # S3 secret key
  host: minio.server          # S3 endpoint host
  port: 80                    # S3 endpoint port
  bucket: backup              # S3 bucket name
  insecure: true              # Use HTTP instead of HTTPS
  prefix: spilo/acid-database/shasum/logical_backups  # S3 prefix path
  suffix: .sql.gz             # Backup file suffix
```

##### Application Database Configuration
```yaml
application:
  image: postgres             # Database image
  tag: latest                 # Image tag
  port: 5432                  # Database port
  storage: 10Gi               # Persistent volume size
  mount: /var/lib/postgresql/data  # Database data mount path
  env:                        # Environment variables
    - name: POSTGRES_PASSWORD
      value: passw0rd
    - name: POSTGRES_USER
      value: aldaas
    - name: POSTGRES_DB
      value: my_db_name
  resources:                  # Resource limits and requests
    requests:
      cpu: 100m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 1Gi
```

##### Restore Job Configuration
```yaml
restore:
  args:
    - gunzip -c /backup.sql.gz | psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB
  command:
    - sh
    - -c
  env:
    - name: PGPASSWORD
      value: passw0rd
    - name: POSTGRES_USER
      value: aldaas
    - name: POSTGRES_DB
      value: my_db_name
```

##### Health Check Configuration
```yaml
check:
  args:
    - psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB -c "\l"
  command:
    - sh
    - -c
```

### 3. Workflow Templates

#### Main Workflow Template (`generator-application.yaml`)

The primary workflow template creates database instances from snapshots.

**Entry Point**: `init`

**Parameters**:
- `ttl` (default: 300): Time-to-live in seconds

**Workflow Steps**:
1. `get-last-snapshot`: Retrieves the latest volume snapshot
2. `create-pvc-from-snapshot`: Creates PVC from snapshot
3. `create-deployment`: Creates database deployment
4. `create-service`: Creates Kubernetes service
5. `create-ingress`: Creates ingress for WebSocket access
6. `wait-service`: Waits for service to be ready

### 4. Event-Driven Automation

#### Event Source (`create-event-source.yaml`)

Monitors S3 bucket for new backup files.

**Configuration**:
```yaml
spec:
  minio:
    webhook:
      endpoint: "{{.Values.s3.host}}:{{.Values.s3.port}}"
      bucket:
        name: "{{.Values.s3.bucket}}"
      events:
        - "s3:ObjectCreated:*"
```

#### Event Sensor (`create-event-sensor.yaml`)

Triggers workflow when new backup is detected.

**Trigger**: Creates new workflow from template when S3 object is created
**Parameters**: Passes S3 object key as `db-file` parameter

### 5. Cleanup and Monitoring

#### Cleanup CronJob (`cleanup-cron.yaml`)

Removes expired database instances based on TTL.

**Schedule**: Configurable via cron expression
**Function**: Deletes workflows and associated resources past their TTL

#### Metrics Collection (`metrics-config-map.yaml`)

Provides Prometheus metrics for monitoring.

**Metrics Endpoint**: `http://0.0.0.0:8080/metrics`
**Script**: Python script that collects and exposes workflow metrics

## WebSocket API

### Connection Endpoint

```
wss://{domain}/{aldaas-name}/{token}/{workflow-name}
```

**Parameters**:
- `domain`: Aldaas server domain
- `aldaas-name`: Deployed Aldaas instance name
- `token`: Authentication token
- `workflow-name`: Generated workflow instance name

### Protocol

The WebSocket connection proxies TCP traffic to the database instance using the `tcp-over-websocket` protocol.

## REST API Endpoints

### Health Check
```
GET /health
```
Returns health status of the Aldaas service.

### Metrics
```
GET /metrics
```
Returns Prometheus-formatted metrics for monitoring.

### Workflow Status
```
GET /status/{workflow-name}
```
Returns status information for a specific database instance.

## Installation and Deployment

### Prerequisites

1. Kubernetes cluster (v1.26+) with VolumeSnapshot feature
2. Rook-Ceph with Volume Snapshot Class
3. Argo Events with webhook enabled
4. Argo Workflows with ingress enabled

### Installation Steps

1. **Install using Helm**:
```bash
helm install aldaas ./chart \
  --set domain=your-domain.com \
  --set tunnel.token=your-secret-token \
  --set s3.host=your-s3-host \
  --set s3.accesskey=your-access-key \
  --set s3.secretkey=your-secret-key
```

2. **Configure Fleet (Optional)**:
```bash
# Deploy using Fleet
kubectl apply -f fleet/
```

### Client Usage

1. **Get Argo Token**:
```bash
ARGO_TOKEN=$(argo auth token)
```

2. **Run Client**:
```bash
docker run -it \
  -p 5432:5432 \
  -e ALDAAS_PORT=5432 \
  -e ALDAAS_NAME=aldaas \
  -e ALDAAS_TOKEN=your-token \
  -e ARGO_SERVER=argo.example.com \
  -e ARGO_HTTP1=true \
  -e ARGO_TOKEN=$ARGO_TOKEN \
  -e ARGO_NAMESPACE=aldaas \
  ghcr.io/negashev/aldaas:main
```

3. **Connect to Database**:
```bash
psql -h localhost -p 5432 -U aldaas -d my_db_name
```

## Security Considerations

- Use strong authentication tokens
- Enable TLS for WebSocket connections
- Implement proper RBAC for service accounts
- Secure S3 credentials using Kubernetes secrets
- Configure network policies to restrict access

## Troubleshooting

### Common Issues

1. **Connection Failed**: Check Argo server accessibility and token validity
2. **Workflow Stuck**: Verify storage class and snapshot class configuration
3. **Backup Not Found**: Ensure S3 credentials and bucket configuration are correct
4. **Resource Limits**: Check if cluster has sufficient resources for database instances

### Debug Commands

```bash
# Check workflow status
argo get workflow-name

# View workflow logs
argo logs workflow-name

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Verify storage
kubectl get volumesnapshots
kubectl get pvc
```