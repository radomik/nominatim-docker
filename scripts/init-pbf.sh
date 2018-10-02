#!/bin/bash

env
echo ""

# Initialization parameters (passed as environment parameters)
COUNTRY_LIST=${COUNTRIES:=""}
BUILD_MEMORY=${BUILD_MEMORY:=5}
BUILD_THREADS=${BUILD_THREAD_COUNT:=8}
RUNTIME_THREADS=${RUNTIME_THREAD_COUNT:=4}
RUNTIME_MEMORY=${RUNTIME_MEMORY:=4}
UPDATE_CRON_SETTINGS=${UPDATE_CRON_SETTINGS:="40 4 * * *"}
CRON_LOG_LEVEL=${CRON_LOG_LEVEL:=0}
COUNTRIES=($COUNTRY_LIST)

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

if [ "$(whoami)" != "root" ] ; then
	echo "Script shall be run as root. Current user: $(whoami)"
	exit 1
fi

if [ ${#COUNTRIES[@]} -eq 0 ] ; then
	echo "No countries arguments provided"
	exit 1
fi

OSM2PGSQL_CACHE=$((BUILD_MEMORY * 1024))
OSM2PGSQL_CACHE=$((OSM2PGSQL_CACHE * 3))
OSM2PGSQL_CACHE=$((OSM2PGSQL_CACHE / 4))

echo "Using settings:"
echo "BUILD_MEMORY=$BUILD_MEMORY"
echo "OSM2PGSQL_CACHE=$OSM2PGSQL_CACHE"
echo "BUILD_THREADS=$BUILD_THREADS"
echo "RUNTIME_MEMORY=$RUNTIME_MEMORY"
echo "RUNTIME_THREADS=$RUNTIME_THREADS"
echo "UPDATE_CRON_SETTINGS=$UPDATE_CRON_SETTINGS"
echo "CRON_LOG_LEVEL=$CRON_LOG_LEVEL"
echo ""
echo "Using countries:"
for COUNTRY in "${COUNTRIES[@]}" ; do
  echo "* $COUNTRY"
done
echo ""

USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
NOMINATIM_BUILD="${NOMINATIM_HOME}/build"
PBF_DIR="${NOMINATIM_HOME}/pbf"
PBF_ALL="${PBF_DIR}/data.pbf"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"
INIT_FILE="${NOMINATIM_HOME}/init.lock"

function startup_after_init {	
	echo "Starting system logging deamon"
	rsyslogd
	echo "Starting cron deamon with log level: $CRON_LOG_LEVEL"
	cron -L${CRON_LOG_LEVEL}

	service postgresql start

	tail -f /var/log/apache2/access.log &

	echo "Nominatim started on $(date)"
	# Run Apache in the foreground (to keep docker container running)
	/usr/sbin/apache2ctl -D FOREGROUND
}

function initial_startup {	
	# Wait until data update process is finished
	wait_for_update

	echo "Initializtion started on $(date)"

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
	#todo: Do not convert to o5m if there is only one country imported
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
		sudo -u $USERNAME rm -v ${PBF}
	done

	O5M="data.o5m"
	echo "Merge: *.o5m -> ${O5M}"
	sudo -u $USERNAME ${OSMCONVERT} *.o5m -o=${O5M}
	echo "Convert: ${O5M} -> ${PBF_ALL}"
	sudo -u $USERNAME ${OSMCONVERT} ${O5M} -o=${PBF_ALL}
	sudo -u $USERNAME rm -v *.o5m

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

	sudo -u $USERNAME touch "$INIT_FILE"
	echo "Initializtion finished on $(date)"
	startup_after_init
}

#todo: Add parameter to force initial startup
if [ -f "$INIT_FILE" ] ; then
	echo "$INIT_FILE exists, skip initial procedure"
	startup_after_init
else
	initial_startup
fi
