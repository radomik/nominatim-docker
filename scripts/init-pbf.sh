#!/bin/bash

function wait_for_update {
	local update_lock_dir="/var/run/nominatim-update.lock"
	if [ -d "$update_lock_dir" ] ; then
		local t=0
		local t_max=600
		local step=10
		echo "Nominatim update is running. Wait up to $t_max seconds"
		while [ $t -lt $t_max ] ; do
			sleep $step
			t=$((t + step))
			if [ ! -d "$update_lock_dir" ] ; then
				echo "Update finished within $t seconds"
				return
			fi
		done
		echo "Update did not finished within $t seconds"
		exit 1
	fi
}

COUNTRIES=()
BUILD_MEMORY=5
OSM2PGSQL_CACHE=3800
BUILD_THREADS=4
RUNTIME_THREADS=2
RUNTIME_MEMORY=4
UPDATE_CRON_SETTINGS="40 4 * * *"
CRON_LOG_LEVEL=0

if [ $# -eq 0 -o "$1" == "-h" -o "$1" == "--help" ] ; then
	echo -e \
"Available arguments:\n\
	-p europe/country1 -p europe/country2 ...\n\
		List of countries to be imported into Nominatim search engine\n\
	-b <build memory (default: $BUILD_MEMORY GB)>\n\
		Amount of memory in gigabytes used by Postgres database during Nominatim data initial import\n\
	-o <OSM cache size (default: $OSM2PGSQL_CACHE MB)>\n\
		Amount of memory in megabytes used by OSM2PGSQL cache during Nominatim data initial import (shall be 75% of value given in \`-b\` option)\n\
	-t <build thread count (default: $BUILD_THREADS)>\n\
		Thread count used by Postgres during Nominatim data import\n\
	-j <runtime memory (default: $RUNTIME_MEMORY GB)>\n\
		Amount of memory in gigabytes used by Postgres database at runtime\n\
	-r <runtime thread count (default: $RUNTIME_THREADS)>\n\
		Thread count used by Postgres at Nominatim runtime\n\
	-c <data update cron settings (default: '$UPDATE_CRON_SETTINGS')>\n\
		Crontab setting for Nominatim data update cron job (See https://crontab.guru/)\n\
	-L <cron log level (default: $CRON_LOG_LEVEL)>\n\
		Cron log level (see: \`man cron\`)\n\
	"
	exit 0
fi

if [ "$(whoami)" != "root" ] ; then
	echo "Script shall be run as root. Current user: $(whoami)"
	exit 1
fi

while getopts "p:b:o:t:j:r:c:L:" OPT; do
    case "$OPT" in
        p) COUNTRIES+=("$OPTARG") ;;
        b) BUILD_MEMORY="$OPTARG" ;;
        o) OSM2PGSQL_CACHE="$OPTARG" ;;
        t) BUILD_THREADS="$OPTARG" ;;
        j) RUNTIME_MEMORY="$OPTARG" ;;
        r) RUNTIME_THREADS="$OPTARG" ;;
        c) UPDATE_CRON_SETTINGS="$OPTARG" ;;
        L) CRON_LOG_LEVEL="$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
NOMINATIM_BUILD="${NOMINATIM_HOME}/build"
PBF_DIR="${NOMINATIM_HOME}/pbf"
PBF_ALL="${PBF_DIR}/data.pbf"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"

# Wait until data update process is finished
wait_for_update

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

#Setup cron job running update-multiple-countries.sh periodically
UPDATE_SCRIPT="/srv/nominatim/utils/update.sh"
UPDATE_LOG_PATH="/var/log/nominatim-update.log"
CRONJOB="${UPDATE_CRON_SETTINGS} root $UPDATE_SCRIPT $UPDATE_LOG_PATH"
CRONJOB_FILE="/etc/cron.d/nominatim-update"
echo "MAILTO=\"\"" > "$CRONJOB_FILE"
echo "$CRONJOB" >> "$CRONJOB_FILE"
chmod +x "$UPDATE_SCRIPT"
chmod +x "$CRONJOB_FILE"
crontab "$CRONJOB_FILE"

echo "Configured cron job for Nominatim data update:"
cat "$CRONJOB_FILE"

echo "Starting system logging deamon"
rsyslogd
echo "Starting cron deamon with log level: $CRON_LOG_LEVEL"
cron -L${CRON_LOG_LEVEL}

service postgresql start

tail -f /var/log/apache2/access.log &

echo "Initializtion finished on $(date)"

# Run Apache in the foreground (to keep docker container running)
/usr/sbin/apache2ctl -D FOREGROUND
