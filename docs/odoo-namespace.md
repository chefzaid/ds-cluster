# Odoo namespace

Odoo is owned by `bm-cluster` in `corp`. The `apps` namespace is reserved for
first-party applications and is the scope of automatic source analysis.
`appsEnabled` still enables both application namespaces and corporate workloads.
Odoo uses the shared PostgreSQL service in `infra`; its database, public hostname,
Keycloak client and Vault paths do not change. TLS reconciliation includes `corp`.
The namespace has the same admission baseline and default ingress denial as `apps`.

## Migrating an existing installation

A namespace change must be coordinated before GitOps applies the new manifests.
A PVC cannot change namespace. Do not let Argo prune the old claim under its
normal `Delete` reclaim policy or provision a second, empty Odoo volume.

1. Prepare `corp`, TLS, ExternalSecrets, configuration, Service and network policies.
2. Let any current Argo operation finish, disable automated sync temporarily, and
   take a small temporary database/filestore recovery archive and file checksums.
   Block the old Ingress before the recovery capture and stop the old Deployment.
3. Record the existing claim's PV and reclaim policy. Set the PV to `Retain`, then
   delete the old claim only after the old pod has terminated and detached.
4. Create `corp/odoo-data-pvc` with `spec.volumeName` pointing at that same PV.
   Replace the PV's old `claimRef` with the new claim identity and UID. Confirm
   the new claim is Bound to the original CSI volume handle. The binding values
   are operational state, never committed into the manifests.
5. Start Odoo in `corp`, verify health, database records and all pre-move filestore
   hashes, then create its Ingress and verify HTTPS and the Keycloak login link.
6. Publish the namespace change, re-enable Argo, and verify the new revision.
   Remove old Odoo resources from `apps`, including owned reports and Secrets.
   Restore the PV's original reclaim policy only after the new binding is healthy.
7. Delete the temporary recovery archives after verification. Confirm Longhorn
   still has the same volume count and that no duplicate volume or snapshot was
   left behind. Keep only small, non-sensitive migration evidence.

If startup fails, keep Argo paused and the PV retained. Stop the new Deployment
before rebinding that same volume back to a recreated old claim. Restore the old
routing only once the original pod is healthy. Never attach both workloads to
separate copies of the data. See [Kubernetes retained volume recovery](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming).
