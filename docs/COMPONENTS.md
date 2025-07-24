# Aldaas Components Documentation

## Overview

This document provides detailed information about all Aldaas components, their functions, and configuration options.

## Helm Chart Components

### Core Templates

#### 1. Workflow Template (`generator-application.yaml`)

The main component that defines the database instance creation workflow.

**Template Functions**:
- Creates temporary database instances from volume snapshots
- Manages lifecycle from creation to cleanup
- Provides WebSocket proxy access to databases

**Key Features**:
- **Snapshot Management**: Automatically selects the latest volume snapshot
- **Dynamic PVC Creation**: Creates persistent volume claims from snapshots
- **Service Mesh Integration**: Creates services and ingresses for access
- **TTL Support**: Automatic cleanup based on configurable time-to-live

**Template Structure**:
```yaml
spec:
  entrypoint: init
  templates:
    - name: init                    # Main orchestration
    - name: get-last-snapshot      # Snapshot discovery
    - name: create-pvc-from-snapshot # Storage provisioning
    - name: create-deploment       # Database deployment
    - name: create-service         # Service creation
    - name: create-ingress         # Ingress configuration
    - name: wait-service           # Health checking
```

#### 2. Event Source (`create-event-source.yaml`)

Monitors S3 storage for new backup files.

**Function**: 
- Listens for S3 ObjectCreated events
- Triggers automated workflow creation when new backups arrive

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
      filter:
        prefix: "{{.Values.s3.prefix}}"
        suffix: "{{.Values.s3.suffix}}"
```

#### 3. Event Sensor (`create-event-sensor.yaml`)

Processes S3 events and creates database instances.

**Workflow**:
1. Receives S3 event notification
2. Extracts backup file information
3. Creates workflow with backup parameters
4. Monitors workflow completion

**Key Features**:
- **Automated Backup Processing**: Creates snapshots from new S3 backups
- **Parameter Injection**: Passes S3 object metadata to workflows
- **Error Handling**: Implements retry strategies for failed operations

#### 4. Cleanup CronJob (`cleanup-cron.yaml`)

Manages cleanup of expired database instances.

**Function**:
- Runs on configurable schedule
- Identifies expired workflows based on TTL
- Removes associated resources (PVCs, Services, Ingresses)

**Template Structure**:
```yaml
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: rancher/kubectl
            command:
            - /script/cleanup.sh
```

### Helper Templates

#### 1. Template Helpers (`_helpers.tpl`)

Provides reusable template functions.

**Functions**:
- `aldaas.fullname`: Generates consistent resource names
- `s3.credentials`: Manages S3 credential references

#### 2. RBAC Configuration (`rbac.yaml`)

Defines necessary permissions for Aldaas operation.

**Permissions**:
- Workflow management (create, get, list, watch, delete)
- PVC operations (create, get, list, delete)
- Service and Ingress management
- Volume snapshot access
- Event management

**Service Account**: Uses `argo-workflow` service account with extended permissions

#### 3. Metrics ConfigMap (`metrics-config-map.yaml`)

Provides monitoring capabilities.

**Metrics Collection Script**:
```python
# Collects metrics from workflow instances
# Exposes Prometheus-compatible metrics
# Monitors database instance health and usage
```

**Metrics Exposed**:
- Active database instances
- Workflow execution times
- Resource utilization
- Error rates

## Fleet Configurations

### 1. Ceph Storage (`fleet/ceph/fleet.yaml`)

Configures Rook-Ceph cluster for storage management.

**Components**:
- **Ceph Cluster**: Distributed storage cluster
- **Storage Classes**: Block and filesystem storage
- **Volume Snapshot Classes**: Snapshot functionality
- **Dashboard**: Web-based management interface

**Configuration Options**:
```yaml
cephClusterSpec:
  dataDirHostPath: /var/lib/rook
  mgr:
    count: 1
    modules:
      - name: pg_autoscaler
        enabled: true
  dashboard:
    enabled: true
    ssl: false
  mon:
    count: 3
    allowMultiplePerNode: false
  storage:
    storageClassDeviceSets:
    - name: osd-pool
      count: 3
      portable: true
```

### 2. Argo Workflows (`fleet/argo/workflow/fleet.yaml`)

Configures Argo Workflows for orchestration.

**Features**:
- **Server Configuration**: Web UI and API access
- **Controller Settings**: Workflow execution engine
- **Ingress Setup**: External access configuration
- **Resource Management**: CPU and memory limits

**Key Settings**:
```yaml
server:
  ingress:
    enabled: true
    hosts:
    - argo.rd.localhost
controller:
  workflowNamespaces:
  - aldaas
  - argo-events
  - argo-workflows
  workflowDefaults:
    spec:
      serviceAccountName: argo-workflow
```

### 3. Argo Events (`fleet/argo/events/fleet.yaml`)

Sets up event-driven automation.

**Components**:
- **Event Bus**: Message routing infrastructure
- **Event Sources**: External event listeners
- **Sensors**: Event processing logic

### 4. Monitoring (`fleet/monitoring/`)

Provides observability for the entire stack.

**Components**:
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **AlertManager**: Alert routing and notification

## Container Components

### 1. Tunnel Container (`tunnel/Dockerfile`)

Multi-stage build for the client proxy.

**Build Stages**:
1. **Builder**: Compiles `tcp-over-websocket` tool
2. **Argo**: Downloads Argo CLI tools
3. **Aldaas**: Final image with all components

**Components**:
- `tcp-over-websocket`: WebSocket-to-TCP proxy
- `argo`: Argo Workflows CLI
- `aldaas`: Custom shell script for automation

### 2. Tunnel Script (`tunnel/aldaas.sh`)

Client-side automation script.

**Functions**:
- **Workflow Management**: Creates and monitors workflows
- **Session Persistence**: Saves workflow references
- **Health Monitoring**: Maintains connection health
- **Proxy Setup**: Establishes WebSocket tunnel

**Key Operations**:
```bash
# Create or reuse workflow
aldaas_name=`argo submit --from workflowtemplate/$ALDAAS_NAME`

# Monitor workflow status
argo watch $aldaas_name

# Establish proxy connection
tcp-over-websocket client -listen_tcp 0.0.0.0:$ALDAAS_PORT
```

## Resource Dependencies

### Storage Requirements

1. **Volume Snapshots**: Requires CSI driver with snapshot support
2. **Storage Classes**: Configured Rook-Ceph storage classes
3. **Persistent Volumes**: Dynamic provisioning capability

### Network Requirements

1. **Ingress Controller**: For external access to services
2. **Load Balancer**: For service distribution
3. **DNS Resolution**: For service discovery

### Compute Requirements

1. **Minimum Resources**:
   - 2 CPU cores per node
   - 4GB RAM per node
   - 20GB storage per database instance

2. **Recommended Resources**:
   - 4+ CPU cores per node
   - 8GB+ RAM per node
   - SSD storage for better performance

## Configuration Validation

### Helm Chart Validation

```bash
# Validate chart syntax
helm lint ./chart

# Dry run installation
helm install aldaas ./chart --dry-run --debug

# Template validation
helm template aldaas ./chart
```

### Fleet Validation

```bash
# Check Fleet status
kubectl get fleet -A

# Validate configurations
kubectl get gitrepo -A
kubectl get bundle -A
```

### Workflow Validation

```bash
# Validate workflow templates
argo template lint

# Check workflow status
argo list

# Validate service accounts
kubectl get sa argo-workflow
kubectl describe sa argo-workflow
```

## Troubleshooting Guide

### Common Configuration Issues

1. **Storage Class Not Found**:
   ```bash
   kubectl get storageclass
   kubectl get volumesnapshotclass
   ```

2. **RBAC Permissions**:
   ```bash
   kubectl auth can-i create workflows --as=system:serviceaccount:aldaas:argo-workflow
   ```

3. **S3 Connectivity**:
   ```bash
   kubectl run test-s3 --image=alpine --rm -it -- sh
   apk add curl
   curl http://minio.server/minio/health/live
   ```

4. **Event Processing**:
   ```bash
   kubectl get eventsource -A
   kubectl get sensor -A
   kubectl logs -l controller=sensor-controller
   ```

### Performance Optimization

1. **Resource Limits**: Adjust based on workload requirements
2. **Storage Performance**: Use SSD storage for better I/O
3. **Network Optimization**: Configure proper ingress and load balancing
4. **Cleanup Frequency**: Adjust cleanup cron schedule based on usage patterns

## Security Best Practices

### Authentication and Authorization

1. **Service Account Security**:
   - Use minimal required permissions
   - Regularly rotate service account tokens
   - Implement namespace isolation

2. **Secret Management**:
   - Use Kubernetes secrets for sensitive data
   - Enable secret encryption at rest
   - Implement secret rotation policies

3. **Network Security**:
   - Configure network policies
   - Use TLS for all communications
   - Implement ingress security headers

### Data Protection

1. **Backup Encryption**: Encrypt backups at rest and in transit
2. **Database Security**: Use strong passwords and connection encryption
3. **Snapshot Security**: Secure snapshot access with proper RBAC