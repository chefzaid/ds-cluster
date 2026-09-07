# Platform themes

## SonarQube

The installed Community Build does not expose a supported dark-mode preference.
The deployment therefore serves a custom theme using the
[Dark Reader website API](https://github.com/darkreader/darkreader#using-dark-reader-on-a-website),
version 4.9.130, vendored with its MIT license into the
`sonarqube-dark-theme` ConfigMap in `k8s/platform/sonarqube.yaml`.
Its npm archive integrity is recorded in the ConfigMap annotation.

One small upstream adjustment calls `injectProxy` directly from the external
script instead of generating an inline script. The website API already runs in
the page context. This preserves Sonar's Content Security Policy while tracking
its dynamically inserted React styles. The result is minified with esbuild;
the served library is about 110 KiB. Images are excluded from theme analysis,
and the theme's fetch method accepts only the current origin.

A short init container using the existing Sonar image copies its original HTML
entry point into a 1 MiB memory-backed volume and adds same-origin theme assets.
The original application bundles, context placeholders and inline-script hash
remain intact. The main container mounts the entry point and theme files
read-only. No additional service, image, PVC or startup download is needed.

Dark mode is the default. The **Dark / Light** button at the bottom right stores
an opt-out in this browser's local storage (`swirlit.sonar.theme`). It does not
change account credentials, API calls, projects or scanner behavior. Theme
updates require bumping both the pod's theme revision and the asset `?v=` values
in `head.html`, because these assets can be cached.

After Sonar or Dark Reader upgrades, check project lists, project overview,
issues/code and account screens with browser console/CSP checks. Exercise both
toggle states and reload persistence. This is a custom presentation layer and
should be reviewed when Sonar changes its frontend. Removing the theme mounts,
init container, volumes and ConfigMap restores the upstream interface.

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
