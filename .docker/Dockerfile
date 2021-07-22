FROM ubuntu:20.04 as data
COPY --chown=root:root ./chroot-env /layer1
RUN mkdir /layer2 && mv /layer1/bin /layer2

## psql is required for migration
FROM ubuntu:20.04 as postgresql-cli
RUN apt-get update && apt-get  install -y postgresql-client   && rm -rf /var/lib/apt/lists/* && apt-get clean autoclean && apt-get autoremove -y


## layer with cardano db sync library and executables
FROM postgresql-cli as layer2
COPY --chown=root:root ./chroot-env  /layer2
COPY  ./.docker/merge-root.sh /merge-root
RUN bash -e /merge-root /layer2 \
 && rm -rf /layer2 \
 && rm -rf merge-root

## layer with configuration files
FROM  ubuntu:20.04 as layer3
COPY ./.docker/config/ /app/
WORKDIR /app/cardano-db-sync
COPY ./schema ./schema
COPY ./config/*.yaml /app/cardano-db-sync/config/
COPY  ./.docker/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh


FROM postgresql-cli
LABEL "co.elastic.logs/enable"="false" \
        "maintainer"="Sudip Bhattarai" \
        "organization"="Sireto Technology" \
        "support"="sudip@sireto.io"
COPY --from=layer2  / /
COPY --from=layer3 /app /app
VOLUME /var/lib/cdbsync
WORKDIR /app/cardano-db-sync
ENTRYPOINT  bash -e /app/docker-entrypoint.sh

