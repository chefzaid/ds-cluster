FROM docker.io/hashicorp/vault@sha256:5be49781ecf78bfe775c5309c6a4d9f4e9e040b6c885c99eb2b12fb69855e1a2
USER root
RUN apk upgrade --no-cache
USER 100:1000
