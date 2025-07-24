# Aldaas Usage Guide

## Overview

This guide provides step-by-step instructions for using Aldaas to create temporary database instances from production backups.

## Quick Start

### 1. Prerequisites Check

Verify your environment meets the requirements:

```bash
# Check Kubernetes cluster version
kubectl version --short

# Verify required CRDs
kubectl get crd | grep -E "(workflow|sensor|eventsource|volumesnapshot)"

# Check storage classes
kubectl get storageclass
kubectl get volumesnapshotclass
```

### 2. Basic Installation

Install Aldaas using Helm:

```bash
# Add custom values
cat > values.yaml << EOF
domain: aldaas.example.com
tunnel:
  token: "$(openssl rand -hex 32)"
s3:
  host: minio.example.com
  port: 9000
  bucket: database-backups
  accesskey: your-access-key
  secretkey: your-secret-key
application:
  env:
    - name: POSTGRES_PASSWORD
      value: secure-password
    - name: POSTGRES_USER
      value: app_user
    - name: POSTGRES_DB
      value: production_db
EOF

# Install the chart
helm install aldaas ./chart -f values.yaml
```

### 3. Verify Installation

```bash
# Check deployment status
kubectl get pods -l app.kubernetes.io/name=aldaas

# Verify workflow template
argo template list

# Check event components
kubectl get eventsource,sensor
```

## Common Use Cases

### Use Case 1: Development Database Testing

Create a temporary database for development testing:

```bash
# Run the client container
docker run -it --rm \
  -p 5432:5432 \
  -e ALDAAS_PORT=5432 \
  -e ALDAAS_NAME=aldaas \
  -e ALDAAS_TOKEN=your-token \
  -e ARGO_SERVER=argo.example.com \
  -e ARGO_HTTP1=true \
  -e ARGO_TOKEN=$(argo auth token) \
  -e ARGO_NAMESPACE=aldaas \
  -e ALDAAS_TTL=1800 \
  ghcr.io/negashev/aldaas:main
```

Once the container starts and establishes connection:

```bash
# Connect to the database
psql -h localhost -p 5432 -U app_user -d production_db

# Run your tests
\l                    # List databases
\dt                   # List tables
SELECT count(*) FROM users;  # Example query
```

### Use Case 2: CI/CD Pipeline Integration

Integrate Aldaas into your CI/CD pipeline:

```yaml
# .github/workflows/test.yml
name: Database Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      aldaas:
        image: ghcr.io/negashev/aldaas:main
        ports:
          - 5432:5432
        env:
          ALDAAS_PORT: 5432
          ALDAAS_NAME: aldaas
          ALDAAS_TOKEN: ${{ secrets.ALDAAS_TOKEN }}
          ARGO_SERVER: ${{ secrets.ARGO_SERVER }}
          ARGO_TOKEN: ${{ secrets.ARGO_TOKEN }}
          ARGO_NAMESPACE: aldaas
          ALDAAS_TTL: 600
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Wait for database
      run: |
        timeout 300 bash -c 'until pg_isready -h localhost -p 5432; do sleep 5; done'
    
    - name: Run database tests
      run: |
        psql -h localhost -p 5432 -U app_user -d production_db -f tests/migration.sql
        npm test
```

### Use Case 3: Data Migration Testing

Test database migrations against production-like data:

```bash
# Start Aldaas with longer TTL for migration testing
docker run -d --name aldaas-migration \
  -p 5433:5432 \
  -e ALDAAS_PORT=5432 \
  -e ALDAAS_NAME=aldaas \
  -e ALDAAS_TOKEN=your-token \
  -e ARGO_SERVER=argo.example.com \
  -e ARGO_TOKEN=$(argo auth token) \
  -e ARGO_NAMESPACE=aldaas \
  -e ALDAAS_TTL=3600 \
  ghcr.io/negashev/aldaas:main

# Wait for database to be ready
sleep 30

# Run migration scripts
psql -h localhost -p 5433 -U app_user -d production_db << EOF
-- Test your migration
BEGIN;
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;
-- Verify migration
\d users
-- Rollback if needed
ROLLBACK;
EOF

# Cleanup
docker stop aldaas-migration
docker rm aldaas-migration
```

### Use Case 4: Performance Testing

Use Aldaas for performance testing with production data:

```bash
# Start multiple database instances for load testing
for i in {1..3}; do
  docker run -d --name aldaas-perf-$i \
    -p $((5432 + i)):5432 \
    -e ALDAAS_PORT=5432 \
    -e ALDAAS_NAME=aldaas \
    -e ALDAAS_TOKEN=your-token \
    -e ARGO_SERVER=argo.example.com \
    -e ARGO_TOKEN=$(argo auth token) \
    -e ARGO_NAMESPACE=aldaas \
    -e ALDAAS_TTL=2400 \
    ghcr.io/negashev/aldaas:main
done

# Run performance tests
pgbench -h localhost -p 5433 -U app_user -d production_db -c 10 -j 2 -T 300

# Cleanup all instances
for i in {1..3}; do
  docker stop aldaas-perf-$i
  docker rm aldaas-perf-$i
done
```

## Advanced Configuration

### Custom Database Images

Configure Aldaas for different database types:

```yaml
# values-postgres.yaml
application:
  image: postgres
  tag: "13"
  port: 5432
  env:
    - name: POSTGRES_PASSWORD
      value: password
    - name: POSTGRES_USER
      value: postgres
    - name: POSTGRES_DB
      value: mydb

restore:
  args:
    - gunzip -c /backup.sql.gz | psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB
```

```yaml
# values-mysql.yaml
application:
  image: mysql
  tag: "8.0"
  port: 3306
  env:
    - name: MYSQL_ROOT_PASSWORD
      value: rootpassword
    - name: MYSQL_DATABASE
      value: mydb
    - name: MYSQL_USER
      value: appuser
    - name: MYSQL_PASSWORD
      value: password

restore:
  args:
    - gunzip -c /backup.sql.gz | mysql -h $ALDAAS_HOST_DAEMON -P 3306 -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE
```

### Custom Backup Formats

Handle different backup formats:

```yaml
# values-custom-restore.yaml
restore:
  # For pg_dump custom format
  args:
    - pg_restore -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB /backup.dump
  
  # For compressed SQL with custom decompression
  args:
    - |
      case "${BACKUP_FILE##*.}" in
        gz) gunzip -c /backup.sql.gz ;;
        bz2) bunzip2 -c /backup.sql.bz2 ;;
        xz) xz -dc /backup.sql.xz ;;
        *) cat /backup.sql ;;
      esac | psql -h $ALDAAS_HOST_DAEMON -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB
```

### Resource Optimization

Optimize resources based on workload:

```yaml
# values-optimized.yaml
application:
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  storage: 50Gi

restore:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

### Multiple Environment Support

Configure for different environments:

```yaml
# values-staging.yaml
domain: staging-aldaas.example.com
s3:
  bucket: staging-backups
  prefix: staging/database-backups
application:
  env:
    - name: POSTGRES_DB
      value: staging_db
```

```yaml
# values-production.yaml
domain: aldaas.example.com
s3:
  bucket: production-backups
  prefix: production/database-backups
application:
  env:
    - name: POSTGRES_DB
      value: production_db
```

## Monitoring and Observability

### Health Checks

Monitor the health of your Aldaas instances:

```bash
# Check workflow status
argo list

# Monitor specific workflow
argo get workflow-name
argo logs workflow-name

# Check database connectivity
kubectl run test-db --image=postgres:13 --rm -it -- \
  psql -h workflow-name.aldaas.svc.cluster.local -p 5432 -U app_user -d production_db -c "SELECT 1"
```

### Metrics Collection

Access Prometheus metrics:

```bash
# Port forward to metrics endpoint
kubectl port-forward svc/workflow-name 8080:8080

# Query metrics
curl http://localhost:8080/metrics

# Example metrics queries
# Active database instances
curl -s http://localhost:8080/metrics | grep aldaas_active_instances

# Database connection count
curl -s http://localhost:8080/metrics | grep aldaas_connections_total
```

### Log Analysis

Analyze logs for troubleshooting:

```bash
# View workflow logs
argo logs workflow-name

# Check event processing logs
kubectl logs -l controller=sensor-controller -n argo-events

# Monitor S3 event source
kubectl logs -l eventsource-name=minio-aldaas -n aldaas

# Database container logs
kubectl logs deployment/workflow-name -c database
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Connection Timeout

```bash
# Check workflow status
argo get workflow-name

# Verify service is running
kubectl get svc workflow-name

# Check ingress configuration
kubectl get ingress workflow-name

# Test internal connectivity
kubectl run debug --image=alpine --rm -it -- sh
apk add curl
curl -v telnet://workflow-name:5432
```

#### 2. Backup Not Loading

```bash
# Check S3 connectivity
kubectl run s3-test --image=alpine --rm -it -- sh
apk add curl
curl -v http://minio.example.com:9000/bucket-name/

# Verify backup file exists
aws s3 ls s3://bucket-name/path/to/backup.sql.gz

# Check restore job logs
kubectl logs job/workflow-name-restore
```

#### 3. Workflow Stuck

```bash
# Check workflow events
kubectl describe workflow workflow-name

# Look for resource constraints
kubectl top nodes
kubectl top pods

# Check PVC status
kubectl get pvc
kubectl describe pvc workflow-name
```

#### 4. Permission Issues

```bash
# Verify service account permissions
kubectl auth can-i create workflows --as=system:serviceaccount:aldaas:argo-workflow

# Check RBAC configuration
kubectl get clusterrolebinding | grep argo-workflow
kubectl describe clusterrolebinding argo-workflow
```

### Debug Mode

Enable debug mode for detailed logging:

```bash
# Run with debug environment
docker run -it --rm \
  -p 5432:5432 \
  -e ALDAAS_DEBUG=true \
  -e ALDAAS_PORT=5432 \
  -e ALDAAS_NAME=aldaas \
  -e ALDAAS_TOKEN=your-token \
  -e ARGO_SERVER=argo.example.com \
  -e ARGO_TOKEN=$(argo auth token) \
  -e ARGO_NAMESPACE=aldaas \
  ghcr.io/negashev/aldaas:main
```

## Performance Tuning

### Database Configuration

Optimize database settings for your workload:

```yaml
# values-performance.yaml
application:
  env:
    - name: POSTGRES_PASSWORD
      value: password
    - name: POSTGRES_USER
      value: postgres
    - name: POSTGRES_DB
      value: mydb
    # PostgreSQL performance settings
    - name: POSTGRES_SHARED_BUFFERS
      value: "256MB"
    - name: POSTGRES_EFFECTIVE_CACHE_SIZE
      value: "1GB"
    - name: POSTGRES_MAINTENANCE_WORK_MEM
      value: "64MB"
    - name: POSTGRES_CHECKPOINT_COMPLETION_TARGET
      value: "0.7"
    - name: POSTGRES_WAL_BUFFERS
      value: "16MB"
    - name: POSTGRES_DEFAULT_STATISTICS_TARGET
      value: "100"
```

### Storage Optimization

Configure storage for better performance:

```yaml
# values-storage-optimized.yaml
rook:
  storageClassName: ceph-block-ssd  # Use SSD storage class
  volumeSnapshotClassName: ceph-block-ssd

application:
  storage: 100Gi  # Larger storage for better I/O
```

### Network Optimization

Optimize network settings:

```yaml
# values-network-optimized.yaml
tunnel:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-connect-timeout: "3600"
```

## Security Considerations

### Secure Token Management

```bash
# Generate secure tokens
ALDAAS_TOKEN=$(openssl rand -hex 32)
kubectl create secret generic aldaas-token --from-literal=token=$ALDAAS_TOKEN

# Use secret in values
echo "tunnel:
  token: $ALDAAS_TOKEN" > values-secure.yaml
```

### Network Security

```yaml
# values-secure.yaml
tunnel:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    tlsSecretName: aldaas-tls
```

### Database Security

```yaml
# values-secure-db.yaml
application:
  env:
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: postgres-credentials
          key: password
    - name: POSTGRES_USER
      valueFrom:
        secretKeyRef:
          name: postgres-credentials
          key: username
```