# Aldaas Reference Guide

## Environment Variables Reference

### Tunnel Service Variables

| Variable | Type | Default | Description | Required |
|----------|------|---------|-------------|----------|
| `ALDAAS_PROTOCOL` | string | `wss` | WebSocket protocol (ws/wss) | No |
| `ALDAAS_SERVER` | string | `$ARGO_SERVER` | Aldaas server hostname | No |
| `ALDAAS_PORT` | integer | `5432` | Database port to proxy | No |
| `ALDAAS_TTL` | integer | `300` | Time-to-live for database instance (seconds) | No |
| `ALDAAS_NAME` | string | - | Workflow template name | Yes |
| `ALDAAS_TOKEN` | string | - | Authentication token for WebSocket connection | Yes |
| `ALDAAS_DEBUG` | boolean | `false` | Enable debug logging | No |
| `ARGO_SERVER` | string | - | Argo Workflows server URL | Yes |
| `ARGO_TOKEN` | string | - | Argo authentication token | Yes |
| `ARGO_NAMESPACE` | string | `default` | Kubernetes namespace for workflows | No |
| `ARGO_HTTP1` | boolean | `false` | Force HTTP/1.1 for Argo server communication | No |
| `ARGO_SECURE` | boolean | `true` | Use HTTPS for Argo server communication | No |

### Database Environment Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `POSTGRES_PASSWORD` | string | - | PostgreSQL password |
| `POSTGRES_USER` | string | `postgres` | PostgreSQL username |
| `POSTGRES_DB` | string | `postgres` | PostgreSQL database name |
| `PGPASSWORD` | string | - | PostgreSQL password for client connections |
| `MYSQL_ROOT_PASSWORD` | string | - | MySQL root password |
| `MYSQL_PASSWORD` | string | - | MySQL user password |
| `MYSQL_USER` | string | - | MySQL username |
| `MYSQL_DATABASE` | string | - | MySQL database name |

### Restore Job Variables

| Variable | Type | Description |
|----------|------|-------------|
| `ALDAAS_HOST_DAEMON` | string | Database host for restore operations |
| `BACKUP_FILE` | string | Path to backup file being restored |

## Helm Chart Values Reference

### Global Configuration

```yaml
# Global settings
serviceAccountName: argo-workflow  # Service account with necessary RBAC
kubectl: v1.27.9                   # kubectl version for utility containers
jq: 1.7.1                         # jq version for JSON processing
domain: ""                        # Domain for ingress configuration
```

### Event Bus Configuration

```yaml
EventBus:
  enabled: true                   # Enable/disable event bus creation
```

### Tunnel Configuration

```yaml
tunnel:
  image: ghcr.io/negashev/aldaas  # Container image
  tag: main                       # Image tag
  port: 8080                      # WebSocket tunnel port
  token: ""                       # Authentication token (required)
  ingress:
    tlsSecretName: ""             # TLS certificate secret name
    annotations: {}               # Additional ingress annotations
```

### Storage Configuration

```yaml
rook:
  storageClassName: ceph-block           # Storage class for PVCs
  volumeSnapshotClassName: ceph-block    # Volume snapshot class
```

### S3 Configuration

```yaml
s3:
  existingSecret: ""              # Existing Kubernetes secret for credentials
  accesskey: ""                   # S3 access key
  secretkey: ""                   # S3 secret key
  host: minio.server              # S3 endpoint hostname
  port: 80                        # S3 endpoint port
  bucket: backup                  # S3 bucket name
  insecure: true                  # Use HTTP instead of HTTPS
  prefix: spilo/acid-database/shasum/logical_backups  # S3 object prefix
  suffix: .sql.gz                 # Backup file suffix
```

### Application Configuration

```yaml
application:
  image: postgres                 # Database container image
  tag: latest                     # Database image tag
  port: 5432                      # Database service port
  storage: 10Gi                   # Persistent volume size
  mount: /var/lib/postgresql/data # Database data mount path
  args: []                        # Additional container arguments
  command: []                     # Container command override
  env:                           # Environment variables for database
    - name: POSTGRES_PASSWORD
      value: passw0rd
    - name: POSTGRES_USER
      value: aldaas
    - name: POSTGRES_DB
      value: my_db_name
  resources:                      # Resource limits and requests
    requests:
      cpu: 100m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 1Gi
```

### Restore Job Configuration

```yaml
restore:
  args:                          # Command arguments for restore
    - gunzip -c /backup.sql.gz | psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB
  command:                       # Base command for restore
    - sh
    - -c
  env:                          # Environment variables for restore job
    - name: PGPASSWORD
      value: passw0rd
    - name: POSTGRES_USER
      value: aldaas
    - name: POSTGRES_DB
      value: my_db_name
  resources:                    # Resource limits for restore job
    requests:
      cpu: 100m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 1Gi
```

### Health Check Configuration

```yaml
check:
  args:                         # Command arguments for health check
    - psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB -c "\l"
  command:                      # Base command for health check
    - sh
    - -c
```

## API Endpoints

### WebSocket Endpoint

```
wss://{domain}/{aldaas-name}/{token}/{workflow-name}
```

**Method**: WebSocket connection
**Purpose**: Establish TCP-over-WebSocket proxy to database
**Authentication**: Token-based authentication in URL path

**Parameters**:
- `domain`: Configured ingress domain
- `aldaas-name`: Helm release name or custom name
- `token`: Authentication token from values.yaml
- `workflow-name`: Generated workflow instance identifier

### Health Check Endpoint

```
GET /health
```

**Response**:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "version": "0.0.1"
}
```

### Metrics Endpoint

```
GET /metrics
```

**Response**: Prometheus-formatted metrics
**Content-Type**: `text/plain`

**Sample Metrics**:
```
# HELP aldaas_active_instances Number of active database instances
# TYPE aldaas_active_instances gauge
aldaas_active_instances 5

# HELP aldaas_workflows_total Total number of workflows created
# TYPE aldaas_workflows_total counter
aldaas_workflows_total 142

# HELP aldaas_workflow_duration_seconds Time spent in workflow execution
# TYPE aldaas_workflow_duration_seconds histogram
aldaas_workflow_duration_seconds_bucket{le="60"} 45
aldaas_workflow_duration_seconds_bucket{le="300"} 78
aldaas_workflow_duration_seconds_bucket{le="600"} 89
```

### Workflow Status Endpoint

```
GET /status/{workflow-name}
```

**Response**:
```json
{
  "name": "workflow-abc123",
  "status": "Running",
  "created": "2024-01-01T12:00:00Z",
  "ttl": 300,
  "remaining": 245,
  "database": {
    "host": "workflow-abc123.aldaas.svc.cluster.local",
    "port": 5432,
    "ready": true
  }
}
```

## Kubernetes Resources

### Generated Resources

Each workflow instance creates the following Kubernetes resources:

#### PersistentVolumeClaim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {workflow-name}
spec:
  storageClassName: {rook.storageClassName}
  dataSource:
    name: {snapshot-name}
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: {application.storage}
```

#### Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {workflow-name}
spec:
  replicas: 1
  selector:
    matchLabels:
      aldaas: {workflow-name}
  template:
    spec:
      containers:
      - name: database
        image: {application.image}:{application.tag}
        ports:
        - containerPort: {application.port}
        env: {application.env}
        resources: {application.resources}
        volumeMounts:
        - name: data
          mountPath: {application.mount}
      - name: tunnel
        image: {tunnel.image}:{tunnel.tag}
        ports:
        - containerPort: {tunnel.port}
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: {workflow-name}
```

#### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {workflow-name}
spec:
  ports:
  - port: {application.port}
    targetPort: {application.port}
    name: database
  - port: {tunnel.port}
    targetPort: {tunnel.port}
    name: tunnel
  selector:
    aldaas: {workflow-name}
```

#### Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {workflow-name}
  annotations: {tunnel.ingress.annotations}
spec:
  rules:
  - host: {domain}
    http:
      paths:
      - path: /{aldaas-name}/{token}/{workflow-name}
        pathType: Prefix
        backend:
          service:
            name: {workflow-name}
            port:
              number: {tunnel.port}
  tls:
  - hosts:
    - {domain}
    secretName: {tunnel.ingress.tlsSecretName}
```

## Fleet Configuration Reference

### Ceph Configuration

```yaml
# fleet/ceph/fleet.yaml
helm:
  values:
    cephClusterSpec:
      dataDirHostPath: /var/lib/rook     # Host path for Ceph data
      continueUpgradeAfterChecksEvenIfNotHealthy: true
      mgr:
        count: 1                         # Number of manager daemons
        modules:
          - name: pg_autoscaler
            enabled: true
      dashboard:
        enabled: true                    # Enable Ceph dashboard
        ssl: false                       # Disable SSL for dashboard
      mon:
        count: 3                         # Number of monitor daemons
        allowMultiplePerNode: false      # One monitor per node
        volumeClaimTemplate:
          spec:
            storageClassName: {storage-class}
            resources:
              requests:
                storage: 10Gi
      storage:
        storageClassDeviceSets:
        - name: osd-pool
          count: 3                       # Number of OSDs
          portable: true                 # Allow OSD migration
          encrypted: false               # Disable encryption
```

### Argo Workflows Configuration

```yaml
# fleet/argo/workflow/fleet.yaml
helm:
  values:
    server:
      ingress:
        enabled: true                    # Enable ingress for web UI
        hosts:
        - argo.{domain}
      nodeSelector:
        node-role.kubernetes.io/master: "true"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
    controller:
      extraEnv:
      - name: DEFAULT_REQUEUE_TIME
        value: 1s                        # Workflow requeue interval
      resources:
        requests:
          memory: "256Mi"
          cpu: "250m"
        limits:
          memory: "256Mi"
          cpu: "500m"
      workflowNamespaces:                # Allowed namespaces for workflows
      - aldaas
      - argo-events
      - argo-workflows
      workflowDefaults:
        spec:
          serviceAccountName: argo-workflow
```

### Argo Events Configuration

```yaml
# fleet/argo/events/fleet.yaml
helm:
  values:
    webhook:
      enabled: true                      # Enable webhook event source
    controller:
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "256Mi"
```

## RBAC Permissions Reference

### Required Permissions

The service account needs the following permissions:

#### Workflow Management
```yaml
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflowtemplates"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

#### Storage Management
```yaml
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "delete"]

- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["get", "list", "watch"]
```

#### Service Management
```yaml
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch", "create", "delete"]

- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "delete"]

- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "delete"]
```

#### Event Management
```yaml
- apiGroups: ["argoproj.io"]
  resources: ["eventsources", "sensors"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

## Error Codes and Troubleshooting

### Common Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| `E001` | Workflow template not found | Verify template exists: `argo template list` |
| `E002` | Insufficient RBAC permissions | Check service account permissions |
| `E003` | Storage class not found | Verify storage class: `kubectl get storageclass` |
| `E004` | Volume snapshot failed | Check snapshot class and source volume |
| `E005` | S3 connection failed | Verify S3 credentials and network connectivity |
| `E006` | Backup restore failed | Check backup file format and database compatibility |
| `E007` | WebSocket connection timeout | Verify ingress configuration and token |
| `E008` | Database startup failed | Check database configuration and resources |
| `E009` | Workflow TTL exceeded | Increase TTL or check cleanup configuration |
| `E010` | Event processing failed | Check event source and sensor configuration |

### Debug Commands

#### Workflow Debugging
```bash
# List all workflows
argo list

# Get workflow details
argo get {workflow-name}

# View workflow logs
argo logs {workflow-name}

# Describe workflow events
kubectl describe workflow {workflow-name}
```

#### Storage Debugging
```bash
# Check PVC status
kubectl get pvc

# Describe PVC events
kubectl describe pvc {workflow-name}

# List volume snapshots
kubectl get volumesnapshots

# Check storage classes
kubectl get storageclass
```

#### Network Debugging
```bash
# Check service status
kubectl get svc {workflow-name}

# Verify ingress configuration
kubectl get ingress {workflow-name}
kubectl describe ingress {workflow-name}

# Test internal connectivity
kubectl run debug --image=alpine --rm -it -- sh
```

#### Event Debugging
```bash
# Check event sources
kubectl get eventsource

# View sensor status
kubectl get sensor

# Check event logs
kubectl logs -l controller=eventsource-controller
kubectl logs -l controller=sensor-controller
```

## Performance Metrics

### Key Performance Indicators

| Metric | Description | Target |
|--------|-------------|--------|
| Workflow Creation Time | Time to create new database instance | < 60 seconds |
| Database Ready Time | Time for database to accept connections | < 30 seconds |
| Backup Restore Time | Time to restore backup data | Depends on size |
| Resource Utilization | CPU/Memory usage per instance | < 80% allocated |
| Connection Latency | WebSocket proxy latency | < 100ms |
| Cleanup Efficiency | Time to cleanup expired instances | < 60 seconds |

### Monitoring Queries

#### Prometheus Queries
```promql
# Active database instances
aldaas_active_instances

# Workflow success rate
rate(aldaas_workflows_successful_total[5m]) / rate(aldaas_workflows_total[5m])

# Average workflow duration
histogram_quantile(0.95, rate(aldaas_workflow_duration_seconds_bucket[5m]))

# Resource utilization
rate(container_cpu_usage_seconds_total{pod=~"aldaas-.*"}[5m])
container_memory_working_set_bytes{pod=~"aldaas-.*"}
```

#### Grafana Dashboard Panels
- Active Instances (Single Stat)
- Workflow Creation Rate (Graph)
- Success Rate (Single Stat)
- Duration Distribution (Heatmap)
- Resource Usage (Graph)
- Error Rate (Graph)

## Security Considerations

### Token Security
- Use strong, randomly generated tokens
- Rotate tokens regularly
- Store tokens as Kubernetes secrets
- Limit token scope and lifetime

### Network Security
- Enable TLS for all connections
- Use network policies to restrict access
- Implement proper ingress authentication
- Monitor for unauthorized access attempts

### Data Security
- Encrypt backups at rest and in transit
- Use secure database passwords
- Implement proper access controls
- Audit database access logs

### Container Security
- Use minimal base images
- Regularly update container images
- Implement resource limits
- Run containers as non-root users when possible