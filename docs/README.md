# Aldaas – App with Large Data as a Service

## Overview
Aldaas ("App with **L**arge **D**ata **a**s **a** **S**ervice") provides on-demand, production-like database instances for developers and CI/CD pipelines. It automatically clones a fresh copy of a source database from backup, exposes it through a lightweight TCP-over-WebSocket tunnel, and cleans up the temporary database after a configurable TTL.

The project is composed of several sub-systems that work together inside Kubernetes:

1. **Rook-Ceph** – persistent storage + CSI snapshots.
2. **Argo Workflows & Argo Events** – orchestration of workspace (DB) lifecycle.
3. **Helm chart `aldaas/`** – deploys Aldaas operators (event-sources, sensors, workflows, RBAC, etc.).
4. **Tunnel image (`ghcr.io/negashev/aldaas`)** – minimal client that opens a local TCP port and forwards it to the Kubernetes cluster via WebSocket.
5. **Fleet bundles (`fleet/`)** – optional quick-start manifests that install Ceph, Rook and Argo in a Rancher/Fleet-managed cluster.

High-level flow:

```text
Developer ↔ Aldaas tunnel (tcp-over-websocket) ↔ Ingress ↔ Argo Workflow ↔ DB Pod ↔ Ceph Snapshot
```

## Public APIs & Entry Points

| Interface | Description | Default | Example |
|-----------|-------------|---------|---------|
| **WebSocket** `wss://<domain>/<ALDAAS_NAME>/<ALDAAS_TOKEN>/<workflow-name>` | Main data tunnel. The path parameters identify the Helm release (`ALDAAS_NAME`), shared token (`ALDAAS_TOKEN`) and the current Argo workflow name. | `ALDAAS_PROTOCOL=wss` | `wss://aldaas.example.com/postgres/9fK…/aldaas-postgres-vhkd9` |
| **Argo Workflows** | WorkflowTemplate `<ALDAAS_NAME>` creates the DB from backup, waits until it is ready, and finally deletes it after TTL. Triggered by Aldaas tunnel startup. | – | `argo submit --from workflowtemplate/postgres -p ttl=300` |
| **Helm Values.yaml** | Configuration API for cluster operators (see below). | – | `helm install aldaas ./chart -f my-values.yaml` |

## Installation

### Prerequisites
1. Kubernetes **1.26+** with the **VolumeSnapshot** feature gate enabled.
2. Ingress controller (nginx, traefik, etc.) with TLS termination (optional but recommended).
3. Rook-Ceph deployed and a `VolumeSnapshotClass` available (Fleet bundle provided).
4. Argo Workflows **v3.5+** and Argo Events **v1.8+** (Fleet bundle provided).

### Quick-start with Fleet (Rancher)
If you use Rancher Fleet you can bootstrap the entire stack with:

```bash
# Ceph storage
kubectl apply -f fleet/ceph/fleet.yaml

# Rook operator & CRDs
await …

# Argo stack
kubectl apply -f fleet/argo/fleet.yaml
```

### Installing Aldaas Helm chart

```bash
helm repo add aldaas https://github.com/Negashev/aldaas
helm install aldaas aldaas/chart \
  --namespace aldaas --create-namespace \
  --set tunnel.token="$(openssl rand -hex 32)" \
  --set domain="aldaas.example.com"
```

## Helm Chart Reference (`chart/values.yaml`)

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `serviceAccountName` | string | `argo-workflow` | Name of Argo Workflow SA to be used by Aldaas jobs. Must have RBAC to create PVCs, snapshots, workflows. |
| `kubectl` | string | `v1.27.9` | kubectl image tag used inside init/cleanup jobs. |
| `jq` | string | `1.7.1` | jq image tag used inside init/cleanup jobs. |
| `EventBus.enabled` | bool | `true` | Whether to create the default Argo EventBus in the release namespace. |
| `domain` | string | `""` | Base DNS name (without protocol) that will be placed into generated ingress rules. |
| `tunnel.image` | string | `ghcr.io/negashev/aldaas` | Container image for the Aldaas tunnel client. |
| `tunnel.tag` | string | `main` | Image tag. |
| `tunnel.port` | int | `8080` | Service port exposed by the tunnel Deployment (WebSocket). |
| `tunnel.token` | string | **REQUIRED** | Shared secret token used by both the tunnel ingress and client to authenticate the connection. |
| `tunnel.ingress.tlsSecretName` | string | `""` | Name of a pre-existing TLS secret. Leave empty to serve plain HTTP/WS. |
| `tunnel.ingress.annotations` | map | `{}` | Extra annotations for the generated Ingress (e.g. cert-manager). |
| `rook.storageClassName` | string | `ceph-block` | Rook storage class used for PVCs. |
| `rook.volumeSnapshotClassName` | string | `ceph-block` | Rook snapshot class. |
| `s3.*` | – | *(see file)* | MinIO/S3 credentials and location of logical backup objects. Either set `existingSecret` **or** inline `accesskey/secretkey`. |
| `application.image` | string | `postgres` | Container image for the restored DB. |
| `application.tag` | string | `latest` | Tag of the DB image. |
| `application.storage` | string | `10Gi` | PVC size for each temporary DB instance. |
| `application.env` | list | *(see file)* | Environment variables (user, password, database) passed to the Postgres container. |
| `restore.*` | – | *(see file)* | Command executed inside a helper Pod that restores the backup. Usually `gunzip | psql`. |
| `check.*` | – | *(see file)* | Liveness probe used by workflow to verify DB is ready after restore. |

> 📝 **Tip**: For a full and always up-to-date list inspect `chart/values.yaml`.

### Example: minimal custom `values.yaml`

```yaml
domain: aldaas.example.com

tunnel:
  token: "$(openssl rand -hex 32)"
  ingress:
    tlsSecretName: aldaas-tls

s3:
  existingSecret: my-backup-creds
  host: minio.storage
  bucket: backups
  prefix: spilo/acid-database/logical_backups

application:
  image: postgres
  tag: 15
  env:
    - name: POSTGRES_PASSWORD
      value: supersecret
```

## Tunnel Client (`tunnel/aldaas.sh`)

The tunnel image contains a tiny shell script that orchestrates the connection between your local workstation and the Aldaas cluster.

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ALDAAS_PROTOCOL` | `wss` | `ws` for plain-text or `wss` for TLS. |
| `ALDAAS_SERVER` | `$ARGO_SERVER` | Hostname of the Aldaas ingress. |
| `ALDAAS_PORT` | `5432` | Local TCP port to listen on (Postgres default). |
| `ALDAAS_TTL` | `300` | Time-to-live (seconds) for the temporary DB. Passed to the workflow. |
| `ALDAAS_NAME` | *(from Helm chart)* | Helm release name (forms the first path segment). |
| `ALDAAS_TOKEN` | *(from Helm chart)* | Shared token (second path segment). |

### Quick client run

```bash
# 1. Download & run the tunnel image (Podman/Docker)
docker run --rm -it \
  -e ALDAAS_SERVER="aldaas.example.com" \
  -e ALDAAS_NAME="postgres" \
  -e ALDAAS_TOKEN="9fK…" \
  -p 5432:5432 \
  ghcr.io/negashev/aldaas:main

# 2. Connect with psql – database will be cloned on-demand
PGPASSWORD=supersecret psql -h localhost -U aldaas -d my_db_name
```

Under the hood the script will:
1. Reuse a saved workflow name if the process has been run recently.
2. Create a new Argo workflow from `WorkflowTemplate/$ALDAAS_NAME` if necessary (`argo submit …`).
3. Start a local **tcp-over-websocket** client mapping `localhost:$ALDAAS_PORT` to the tunnel service inside the cluster.

The workflow will be automatically deleted once TTL is reached and no active tunnel sessions remain.

## Cleaning Up

To remove all Aldaas resources including snapshots, PVCs and DB Pods:

```bash
helm uninstall aldaas -n aldaas
# Optionally: delete snapshots
kubectl delete volumesnapshots -l aldaas.tmpdb=true -n aldaas
```

---

© 2024 Aldaas contributors – Licensed under the MIT License. See `LICENSE` for details.