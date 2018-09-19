#!/bin/bash

COUNTRIES=()
BUILD_MEMORY=32
OSM2PGSQL_CACHE=24000
BUILD_THREADS=16
RUNTIME_THREADS=2
RUNTIME_MEMORY=8

if [ $# -eq 0 -o "$1" == "-h" -o "$1" == "--help" ] ; then
	echo -e "Usage $0\n\
	-p europe/country1 -p europe/country2 ...\n\
	-b <build memory in GB (default: $BUILD_MEMORY GB)>\n\
	-j <runtime memory in GB (default: $RUNTIME_MEMORY GB)>\n\
	-o <OSM cache in MB - shall be 75% of build memory (default: $OSM2PGSQL_CACHE MB)>\n\
	-t <build thread count (default: $BUILD_THREADS)>\n\
	-r <runtime thread count (default: $RUNTIME_THREADS)>\n\
	"
	exit 0
fi

if [ "$(whoami)" != "root" ] ; then
	echo "Script shall be run as root. Current user: $(whoami)"
	exit 1
fi

while getopts "p:b:j:o:t:r:" OPT; do
    case "$OPT" in
        p) COUNTRIES+=("$OPTARG") ;;
        b) BUILD_MEMORY="$OPTARG" ;;
        j) RUNTIME_MEMORY="$OPTARG" ;;
        o) OSM2PGSQL_CACHE="$OPTARG" ;;
        t) BUILD_THREADS="$OPTARG" ;;
        r) RUNTIME_THREADS="$OPTARG" ;;
    esac
done
shift $((OPTIND -1))

USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
NOMINATIM_BUILD="${NOMINATIM_HOME}/build"
PBF_DIR="${NOMINATIM_HOME}/pbf"
PBF_ALL="${PBF_DIR}/data.pbf"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"

service postgresql stop
service apache2 stop

# Download country_grid.sql.gz (optional)
echo "Fetching country grid"
cd ${NOMINATIM_HOME}
sudo -u $USERNAME wget -q -O ./data/country_osm_grid.sql.gz \
      http://www.nominatim.org/data/country_grid.sql.gz

# Download data for initial import
echo "Fetching country PBF files"
OSMCONVERT="${NOMINATIM_HOME}/utils/osmconvert"
sudo -u $USERNAME rm -r ${PBF_DIR}
sudo -u $USERNAME mkdir ${PBF_DIR}
cd ${PBF_DIR}
rm -v "$COUNTRY_LIST"
for COUNTRY in "${COUNTRIES[@]}" ; do
	sudo -u $USERNAME echo "$COUNTRY" >> "$COUNTRY_LIST"
	URL="http://download.geofabrik.de/${COUNTRY}-latest.osm.pbf"
	PBF=`echo "$URL" | sed 's:.*/::'`
	O5M=$(echo ${PBF} | sed 's/.osm.pbf$/.o5m/g')
	echo "Fetch ${URL} to ${PBF}"
	sudo -u $USERNAME wget -q -O "$PBF" "${URL}"
	echo "Convert: ${PBF} -> ${O5M}"
	sudo -u $USERNAME ${OSMCONVERT} ${PBF} -o=${O5M}
	sudo -u $USERNAME rm ${PBF}
done

O5M="data.o5m"
echo "Merge: *.o5m -> ${O5M}"
sudo -u $USERNAME ${OSMCONVERT} *.o5m -o=${O5M}
echo "Convert: ${O5M} -> ${PBF_ALL}"
sudo -u $USERNAME ${OSMCONVERT} ${O5M} -o=${PBF_ALL}
sudo -u $USERNAME rm ${O5M}

# Filter administrative boundaries
#TODO: Make if needed based on merlinnot/nominatim-docker

# Tune postgresql configuration for import
PGSQL_VERSION=`cat ${NOMINATIM_HOME}/settings/local.php | egrep "CONST_Postgresql_Version" | awk -F"'" '{print $4}'`
PGCONFIG_URL="https://api.pgconfig.org/v1/tuning/get-config"
IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${BUILD_MEMORY}GB& \
      max_connections=$((8 * ${BUILD_THREADS} + 32))& \
      environment_name=DW& \
      include_pgbadger=false" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    echo "IMPORT_CONFIG_URL: $IMPORT_CONFIG_URL" && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'off\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop

# Initial import
service postgresql start
echo "Loading ${PBF_ALL}"
sudo -u $USERNAME ${NOMINATIM_BUILD}/utils/setup.php \
  --osm-file ${PBF_ALL} \
  --threads ${BUILD_THREADS} \
  --osm2pgsql-cache ${OSM2PGSQL_CACHE} \
  --all
service postgresql stop

# Use safe postgresql configuration
IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${RUNTIME_MEMORY}GB& \
      max_connections=$((8 * ${RUNTIME_THREADS} + 32))& \
      environment_name=WEB& \
      include_pgbadger=true" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    echo "IMPORT_CONFIG_URL: $IMPORT_CONFIG_URL" && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'on\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop
    
service postgresql start

tail -f /var/log/apache2/access.log &

# Run Apache in the foreground
/usr/sbin/apache2ctl -D FOREGROUND
