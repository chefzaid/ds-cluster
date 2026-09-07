FROM ghcr.io/gethomepage/homepage:v2.2.0@sha256:753eeb0cc22ab7baad39ed47cbd1aae14e193dd1b264e965f193a9ea1d1e1bdd
USER root
RUN apk upgrade --no-cache && rm -rf /usr/local/lib/node_modules/npm /opt/yarn-* /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn /usr/local/bin/yarnpkg
USER 10001:10001
