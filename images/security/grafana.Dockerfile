FROM docker.io/grafana/grafana:13.2.1@sha256:f772d434e8fab0049deb2b1b30abd43342bcfca1537614aa8d36080232cf4283
USER root
RUN apk upgrade --no-cache
USER 472:0
