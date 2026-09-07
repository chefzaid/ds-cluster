FROM docker.io/library/postgres@sha256:b939b3851e2cccb017dc4497af63b15e34efa57fba036548773c53b2f16a8871
USER root
# Keep Debian/glibc, PostgreSQL and ICU unchanged: existing indexes depend on their collations.
RUN apt-get update && apt-get install -y --no-install-recommends --only-upgrade libpcre2-8-0 \
    && rm -rf /var/lib/apt/lists/* /usr/local/bin/gosu /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem
# Kubernetes already starts PostgreSQL as its database owner; gosu is unused.
USER 999:999
