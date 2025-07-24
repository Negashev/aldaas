# Aldaas Documentation

Welcome to the comprehensive documentation for Aldaas (**A**pp with **L**arge **D**ata **a**s **a** **S**ervice) - a Kubernetes-native solution for creating temporary database instances from production backups.

## 📖 Documentation Overview

This documentation provides complete coverage of all Aldaas APIs, functions, components, and usage patterns. The documentation is organized into several comprehensive guides:

### [API Documentation](./API.md)
**Complete API reference and configuration guide**
- Core component APIs and interfaces
- Environment variables and configuration options
- WebSocket and REST endpoint specifications
- Helm chart configuration reference
- Installation and deployment instructions
- Security considerations and troubleshooting

### [Components Guide](./COMPONENTS.md)
**Detailed component architecture and functionality**
- Helm chart templates and their functions
- Fleet configurations for infrastructure
- Container components and build process
- Resource dependencies and requirements
- Configuration validation and troubleshooting
- Performance optimization guidelines

### [Usage Guide](./USAGE.md)
**Step-by-step usage instructions and examples**
- Quick start and basic installation
- Common use cases with detailed examples
- Advanced configuration scenarios
- Monitoring and observability setup
- Troubleshooting common issues
- Performance tuning recommendations

### [Reference Guide](./REFERENCE.md)
**Comprehensive reference for all configuration options**
- Complete environment variables reference
- Helm chart values specification
- API endpoints and response formats
- Kubernetes resource templates
- RBAC permissions reference
- Error codes and debug procedures

## 🚀 Quick Start

1. **Prerequisites**: Kubernetes 1.26+, Rook-Ceph, Argo Workflows, Argo Events
2. **Installation**: `helm install aldaas ./chart -f values.yaml`
3. **Usage**: `docker run -it ghcr.io/negashev/aldaas:main`

For detailed instructions, see the [Usage Guide](./USAGE.md).

## 🏗️ Architecture Overview

Aldaas consists of several integrated components:

- **Tunnel Service**: WebSocket-based proxy for database access
- **Workflow Engine**: Argo Workflows for orchestration
- **Event System**: Argo Events for automated backup processing
- **Storage Layer**: Rook-Ceph for snapshot-based provisioning
- **Fleet Management**: GitOps-based infrastructure deployment

## 📋 Key Features

- **On-Demand Database Instances**: Create temporary databases from production snapshots
- **Event-Driven Automation**: Automatic processing of new backups
- **Multi-Database Support**: PostgreSQL, MySQL, and other database engines
- **Secure Access**: Token-based authentication and TLS encryption
- **Resource Management**: Configurable TTL and automatic cleanup
- **Monitoring Integration**: Prometheus metrics and health checks

## 🛠️ Configuration Examples

### Basic PostgreSQL Setup
```yaml
application:
  image: postgres
  tag: "13"
  env:
    - name: POSTGRES_PASSWORD
      value: secure-password
    - name: POSTGRES_DB
      value: production_db
```

### S3 Backup Source
```yaml
s3:
  host: minio.example.com
  bucket: database-backups
  prefix: production/backups
  suffix: .sql.gz
```

### Custom Resource Limits
```yaml
application:
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

## 🔧 Common Use Cases

1. **Development Testing**: Temporary databases for feature development
2. **CI/CD Integration**: Automated testing with production-like data
3. **Migration Testing**: Safe testing of database schema changes
4. **Performance Testing**: Load testing with real data sets
5. **Data Analysis**: Temporary access to production data for analysis

## 📊 Monitoring and Metrics

Aldaas provides comprehensive monitoring through:

- **Health Endpoints**: Service health and readiness checks
- **Prometheus Metrics**: Detailed operational metrics
- **Workflow Tracking**: Complete workflow execution visibility
- **Resource Monitoring**: CPU, memory, and storage utilization

## 🔒 Security Features

- **Token-Based Authentication**: Secure access control
- **TLS Encryption**: Encrypted data transmission
- **RBAC Integration**: Kubernetes role-based access control
- **Network Policies**: Traffic isolation and security
- **Secret Management**: Secure credential storage

## 🚨 Support and Troubleshooting

For troubleshooting common issues:

1. Check the [troubleshooting section](./USAGE.md#troubleshooting) in the Usage Guide
2. Review [error codes](./REFERENCE.md#error-codes-and-troubleshooting) in the Reference Guide
3. Examine [component debugging](./COMPONENTS.md#troubleshooting-guide) information

### Debug Commands
```bash
# Check workflow status
argo list

# View component health
kubectl get pods -l app.kubernetes.io/name=aldaas

# Monitor events
kubectl get events --sort-by='.lastTimestamp'
```

## 📈 Performance Guidelines

- **Resource Planning**: Allocate appropriate CPU/memory based on workload
- **Storage Optimization**: Use SSD storage classes for better performance
- **Network Tuning**: Configure ingress timeouts and connection limits
- **Cleanup Scheduling**: Adjust TTL and cleanup frequency for efficiency

## 🔄 Upgrade and Maintenance

- **Regular Updates**: Keep container images and dependencies current
- **Backup Validation**: Verify backup integrity and restore procedures
- **Monitoring Review**: Regular review of metrics and alerts
- **Security Updates**: Apply security patches and rotate credentials

## 📚 Additional Resources

- **Argo Workflows Documentation**: [https://argoproj.github.io/argo-workflows/](https://argoproj.github.io/argo-workflows/)
- **Argo Events Documentation**: [https://argoproj.github.io/argo-events/](https://argoproj.github.io/argo-events/)
- **Rook-Ceph Documentation**: [https://rook.io/docs/rook/latest/](https://rook.io/docs/rook/latest/)
- **Fleet Documentation**: [https://fleet.rancher.io/](https://fleet.rancher.io/)

## 🤝 Contributing

For contributions and development:

1. Review the component architecture in [COMPONENTS.md](./COMPONENTS.md)
2. Understand the API specifications in [API.md](./API.md)
3. Test with examples from [USAGE.md](./USAGE.md)
4. Validate against requirements in [REFERENCE.md](./REFERENCE.md)

---

**Note**: This documentation covers all public APIs, functions, and components of the Aldaas system. Each guide provides comprehensive information with examples and usage instructions for different aspects of the system.