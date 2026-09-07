FROM docker.io/dbgate/dbgate:7.2.6-alpine@sha256:1568cca2807d17d270287f05832fe362ff02e4a2cae615e466c954cc59fe7fb4
USER root
RUN apk upgrade --no-cache
USER 10001:10001
