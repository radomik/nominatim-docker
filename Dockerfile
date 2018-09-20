FROM ubuntu:bionic as builder

LABEL maintainer Dariusz Mikołajczuk <radomik@gmail.com>

ENV NOMINATIM_VERSION 3.2.0

# Let the container know that there is no TTY
ENV DEBIAN_FRONTEND noninteractive

# Set build variables
ENV PGSQL_VERSION=10
ENV POSTGIS_VERSION=2.4

# Use bash shell only (required for later proper script operation)
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Update packages
USER root
RUN apt-get -y update
RUN apt-get -y full-upgrade

# Update locales
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
    cron \
    anacron \
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

# Create nominatim user account
USER root
ENV USERNAME nominatim
RUN useradd -d ${NOMINATIM_HOME} -s /bin/bash -m ${USERNAME}
RUN chown -R ${USERNAME}:${USERNAME} ${NOMINATIM_HOME}
RUN chmod a+x ${NOMINATIM_HOME}

# Configure Nominatim
USER ${USERNAME}
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
RUN echo "?>" >> ./settings/local.php
RUN cd ${NOMINATIM_HOME}/utils && \
	wget -q http://m.m.i24.cc/osmconvert.c && \
	cc -x c osmconvert.c -lz -O3 -o osmconvert && \
	rm osmconvert.c
	
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

# Allow remote connections to PostgreSQL (optional)
#RUN echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/${PGSQL_VERSION}/main/pg_hba.conf \
# && echo "listen_addresses='*'" >> /etc/postgresql/${PGSQL_VERSION}/main/postgresql.conf
#EXPOSE 5432

# Expose Apache port
EXPOSE 8080

COPY --chown=nominatim scripts/init-pbf.sh ${NOMINATIM_HOME}/utils/
COPY --chown=nominatim scripts/update-multiple-countries.sh ${NOMINATIM_HOME}/utils/update.sh
USER ${USERNAME}
RUN chmod +x ${NOMINATIM_HOME}/utils/init-pbf.sh ${NOMINATIM_HOME}/utils/update.sh

# Init scripts
#COPY scripts/docker-entrypoint.sh /
#USER root
#RUN chmod +x /docker-entrypoint.sh
#ENTRYPOINT ["/docker-entrypoint.sh"]
