FROM docker.io/library/nginx:1.30.4-alpine@sha256:dc5069ad14f19660b141b21236140b91656bf89bbc3e2417c70ae650cd66104c
USER root
RUN apk upgrade --no-cache
USER 10001:10001
