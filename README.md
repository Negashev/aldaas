# aldaas
**A**pp with **L**arge **D**ata **a**s **a** **s**ervice

![Aldaas for everythink](aldaas.jpg?raw=true "Aldaas")

### how it works
- rook.io snapshots!
- argo workflow+events automation
- light client (argo cli + aldaas script) as proxy to large DB

### configuration
I love rancher) and use [fleet](https://fleet.rancher.io) for quick prepare ceph and argo

- create kubernetes cluster (1.26 or high) with VolumeSnapshot feature
- install rook-ceph in with Volume Snapshot Class [see example](https://github.com/Negashev/aldaas/blob/main/fleet/ceph/fleet.yaml)
- install argo-events with `webhook.enabled`
- install argo-workflows with `server.ingress.enabled` and default serviceAccountName for workflow like [`argo-workflow`](https://github.com/Negashev/aldaas/blob/main/fleet/argo/workflow/fleet.yaml#L51)
- install aldaas helm from `./chart`