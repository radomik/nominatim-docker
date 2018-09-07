FROM ubuntu:bionic as builder

LABEL maintainer Dariusz Mikołajczuk <radomik@gmail.com>

ENV NOMINATIM_VERSION 3.2.0

# Let the container know that there is no TTY
ENV DEBIAN_FRONTEND noninteractive

# Set build variables
ARG PGSQL_VERSION=10
ARG POSTGIS_VERSION=2.4
ARG BUILD_THREADS=16

# Use bash shell only (required for later proper script operation)
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Update packages
USER root
RUN apt-get -y update
RUN apt-get -y full-upgrade

# Update locales
USER root
RUN apt-get -y update
RUN apt-get -y full-upgrade
RUN apt-get install -y --no-install-recommends locales
ENV LANG C.UTF-8
RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8

# Install build dependencies
USER root
RUN apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    curl \
    g++ \
    gcc \
	libboost-dev \
	libboost-filesystem-dev \
	libboost-python-dev \
	libboost-system-dev \
	libbz2-dev \
	libexpat1-dev \
	libgeos-dev \
	libgeos++-dev \
	libpq-dev \
	libproj-dev \
	libxml2-dev\
    php \
    postgresql-server-dev-${PGSQL_VERSION} \
    zlib1g-dev \
	apache2 \
    curl \
    libapache2-mod-php \
    osmosis \
    php \
    php-db \
    php-intl \
    php-pear \
    php-pgsql \
    postgresql-${PGSQL_VERSION}-postgis-${POSTGIS_VERSION} \
	postgresql-${PGSQL_VERSION}-postgis-scripts \
	postgresql-contrib-${PGSQL_VERSION} \
	postgresql-server-dev-${PGSQL_VERSION} \
	python \
	python-pip \
	python-setuptools \
    sudo \
    wget

RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /tmp/* /var/tmp/*
  
ENV NOMINATIM_HOME /srv/nominatim
ENV NOMINATIM_BUILD ${NOMINATIM_HOME}/build

# Build Nominatim
USER root
RUN cd /srv \
 && curl --silent -L \
   http://www.nominatim.org/release/Nominatim-${NOMINATIM_VERSION}.tar.bz2 \
   -o v${NOMINATIM_VERSION}.tar.bz2 \
 && tar xf v${NOMINATIM_VERSION}.tar.bz2 \
 && rm v${NOMINATIM_VERSION}.tar.bz2 \
 && mv Nominatim-${NOMINATIM_VERSION} nominatim \
 && cd ${NOMINATIM_HOME} \
 && mkdir ${NOMINATIM_BUILD} \
 && cd ${NOMINATIM_BUILD} \
 && cmake ${NOMINATIM_HOME} \
 && make

# Install osmium
USER root
RUN pip install --upgrade pip
RUN pip install osmium

# Copy the application from the builder image
#TODO: Try this when webpage does not work
#COPY --from=builder /srv/nominatim /srv/nominatim

# Create nominatim user account
USER root
ENV USERNAME nominatim
RUN useradd -d ${NOMINATIM_HOME} -s /bin/bash -m ${USERNAME}
RUN chown -R ${USERNAME}:${USERNAME} ${NOMINATIM_HOME}
RUN chmod a+x ${NOMINATIM_HOME}

# Configure Nominatim
USER ${USERNAME}
ARG REPLICATION_URL=https://planet.osm.org/replication/hour/
WORKDIR ${NOMINATIM_HOME}
ENV FLATNODE_PATH ${NOMINATIM_HOME}/flatnode
ENV PYOSMIUM_PATH /usr/local/bin/pyosmium-get-changes
RUN test -f ${FLATNODE_PATH} || echo "[WARNING] CONST_Osm2pgsql_Flatnode_File not found: ${FLATNODE_PATH}"
RUN test -f ${PYOSMIUM_PATH} || echo "[WARNING] CONST_Pyosmium_Binary not found: ${PYOSMIUM_PATH}"
RUN echo "<?php" > ./settings/local.php
RUN echo "# Paths" >> ./settings/local.php
RUN echo "@define('CONST_Postgresql_Version', '${PGSQL_VERSION}');" >> ./settings/local.php
RUN echo "@define('CONST_Postgis_Version', '${POSTGIS_VERSION}');" >> ./settings/local.php
RUN echo "@define('CONST_Osm2pgsql_Flatnode_File', '${FLATNODE_PATH}');" >> ./settings/local.php
RUN echo "@define('CONST_Pyosmium_Binary', '${PYOSMIUM_PATH}');" >> ./settings/local.php
RUN echo "# Website settings" >> ./settings/local.php
RUN echo "@define('CONST_Website_BaseURL', '/');" >> ./settings/local.php
RUN echo "#TODO: Do not use below settings if there are multiple PBF files in use" >> ./settings/local.php
RUN echo "#TODO: Otherwise use cron job and custom script based approach" >> ./settings/local.php
RUN echo "#@define('CONST_Replication_Url', '${REPLICATION_URL}');" >> ./settings/local.php
RUN echo "#@define('CONST_Replication_MaxInterval', '86400');" >> ./settings/local.php
RUN echo "#@define('CONST_Replication_Update_Interval', '86400');" >> ./settings/local.php
RUN echo "#@define('CONST_Replication_Recheck_Interval', '900');" >> ./settings/local.php
RUN echo "?>" >> ./settings/local.php

# Download country_grid.sql.gz (optional)
USER ${USERNAME}
WORKDIR ${NOMINATIM_HOME}
RUN wget -q -O ./data/country_osm_grid.sql.gz \
      http://www.nominatim.org/data/country_grid.sql.gz

# Download data for initial import
USER ${USERNAME}
ENV PBF_DIR ${NOMINATIM_HOME}/pbf
ARG PBF_URL=https://planet.osm.org/pbf/planet-latest.osm.pbf
RUN echo "Fetch: ${PBF_URL}"; \
	rm -r ${PBF_DIR} ; \
	mkdir ${PBF_DIR} ; \
    read -a PBF_URL_ARRAY <<< ${PBF_URL} ; \
    cd ${PBF_DIR} ; \
    for URL in "${PBF_URL_ARRAY[@]}" ; do \
		echo "Fetch ${URL}" ; \
		wget -q "${URL}" ; \
    done
    
# Join PBF files into one
USER ${USERNAME}
ENV PBF_ALL=${PBF_DIR}/data.pbf
RUN \
    cd ${PBF_DIR} ; \
    wget -q http://m.m.i24.cc/osmconvert.c ; \
    cc -x c osmconvert.c -lz -O3 -o osmconvert ; \
	for PBF in ${PBF_DIR}/*.pbf; do \
		O5M=$(echo ${PBF} | sed 's/.osm.pbf$/.o5m/g') ; \
		echo "Convert: ${PBF} -> ${O5M}" ; \
		./osmconvert ${PBF} -o=${O5M} ; \
		rm ${PBF} ; \
		O5M=${PBF_DIR}/data.o5m ; \
		echo "Merge: *.o5m -> ${O5M}" ; \
		./osmconvert ${PBF_DIR}/*.o5m -o=${O5M} ; \
		echo "Convert: ${O5M} -> ${PBF_ALL}" ; \
		./osmconvert ${O5M} -o=${PBF_ALL} ; \
		rm ${O5M} ; \
	done ; \
	rm osmconvert.c osmconvert

# Filter administrative boundaries
#TODO: Make if needed based on merlinnot/nominatim-docker

# Configure Apache
ENV INTERNAL_LISTEN_PORT 8080
USER root
RUN echo -e "Listen ${INTERNAL_LISTEN_PORT}\n\
<VirtualHost *:${INTERNAL_LISTEN_PORT}>\n\
  DocumentRoot ${NOMINATIM_BUILD}/website\n\
  CustomLog /var/log/apache2/access.log combined\n\
  ErrorLog /var/log/apache2/error.log\n\
  LogLevel debug\n\
  <Directory ${NOMINATIM_BUILD}/website>\n\
    Options FollowSymLinks MultiViews\n\
    DirectoryIndex search.php\n\
    Require all granted\n\
  </Directory>\n\
  AddType text/html .php\n\
</VirtualHost>\n" > /etc/apache2/sites-enabled/000-default.conf

# Add postgres users
USER root
RUN service postgresql start && \
    sudo -u postgres createuser -s nominatim && \
    sudo -u postgres createuser www-data && \
    service postgresql stop

# Tune postgresql configuration for import
USER root
ARG BUILD_MEMORY=32GB
ENV PGCONFIG_URL https://api.pgconfig.org/v1/tuning/get-config
RUN IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${BUILD_MEMORY}& \
      max_connections=$((8 * ${BUILD_THREADS} + 32))& \
      environment_name=DW& \
      include_pgbadger=false" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'off\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop

# Initial import
USER root
ARG OSM2PGSQL_CACHE=24000
RUN service postgresql start ; \
	echo "Loading ${PBF_ALL}" ; \
	sudo -u nominatim ${NOMINATIM_BUILD}/utils/setup.php \
	  --osm-file ${PBF_ALL} \
	  --threads ${BUILD_THREADS} \
	  --osm2pgsql-cache ${OSM2PGSQL_CACHE} \
	  --all ; \
    service postgresql stop

# Use safe postgresql configuration
USER root
ARG RUNTIME_THREADS=2
ARG RUNTIME_MEMORY=8GB
RUN IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${RUNTIME_MEMORY}& \
      max_connections=$((8 * ${RUNTIME_THREADS} + 32))& \
      environment_name=WEB& \
      include_pgbadger=true" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'on\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop

# Allow remote connections to PostgreSQL (optional)
RUN echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/${PGSQL_VERSION}/main/pg_hba.conf \
 && echo "listen_addresses='*'" >> /etc/postgresql/${PGSQL_VERSION}/main/postgresql.conf
EXPOSE 5432

# Expose ports
EXPOSE 8080

# Init scripts
COPY scripts/docker-entrypoint.sh /
USER root
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
