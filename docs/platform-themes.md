# Platform themes

## Odoo

The Odoo Community 19 deployment includes OCA's `web_dark_mode` 19.0.1.0.0,
pinned to [OCA/web revision b96307a8953f3bae075b8f7d94f40f00c2e63d1f](https://github.com/OCA/web/tree/b96307a8953f3bae075b8f7d94f40f00c2e63d1f/web_dark_mode).
Its unmodified source, translations, tests, attribution and AGPL-3 license are
vendored into the `odoo-dark-mode-addon` ConfigMap in `k8s/corp/odoo.yaml`.
ConfigMap items preserve the upstream directory layout. Both database bootstrap
and the application mount it read-only at `/mnt/extra-addons/web_dark_mode`.
No startup downloads, image builds or additional PVCs are required.

Bootstrap installs the module and enables dark mode for the managed administrator
once, recording `bm_cluster.dark_mode_initialized` in Odoo's configuration.
Later changes through the user menu's **Dark Mode** switch survive pod restarts.
Other users choose their own preference; the add-on also supports matching the
device theme in user preferences. This changes the authenticated Odoo backend.

After changing the vendored module, update its upstream annotation and the
Deployment's configuration revision, then validate the repository and test an
authenticated `/odoo` page. Confirm the dark CSS bundle loads successfully and
the user-menu switch works in both directions. Review the upstream module for
compatibility before upgrading Odoo's major version. To disable dark mode, use
the switch. Before removing the add-on files, uninstall the module from Odoo.
