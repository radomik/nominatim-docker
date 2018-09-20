#!/bin/bash
# Usage:
# ./update-multiple-countries.sh [<log file>]

OUT="/dev/stdout"
if [ $# -gt 0 ] ; then
	OUT="$1"
fi

LOCKED=0
LOCK_DIR="/var/run/nominatim-update.lock"

function release_lock {
	if ((${LOCKED})); then
		echo "Release lock"
		rmdir "$LOCK_DIR"
		LOCKED=0
	fi
}

function onexit {
	if [ ! -z "$1" ] ; then
		echo "[ERROR] $1" >>"$OUT" 2>&1
		if [ "$OUT" != "/dev/stdout" ] ; then
			echo "[ERROR] $1"
		fi
	else
		echo "Exiting succesfully" >>"$OUT" 2>&1
	fi
	if [ -f "$OUT" ] ; then
		OUT_SIZE=`du -b "$OUT" | cut -f1`
		if [ $OUT_SIZE -ge $((1024 * 1024)) ] ; then
			rm -f "$OUT"
		fi
	fi
	release_lock
	if [ ! -z "$1" ] ; then
		exit 1
	fi
	exit 0
}

function acquire_lock {
	if mkdir "$LOCK_DIR"; then
		LOCKED=1
		trap "release_lock" EXIT
	else
		onexit "Update script already running"
	fi
}}

if [ "$(whoami)" != "root" ] ; then
	onexit "Script shall be run as root. Current user: $(whoami)" 
fi

USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"
BUILD_DIR="${NOMINATIM_HOME}/build"
UPDATE_PHP="./utils/update.php"

id -u "$USERNAME" >/dev/null 2>&1
if [ $? -ne 0 ] ; then
	onexit "User '$USERNAME' does not exist"
fi
if [ ! -d "$NOMINATIM_HOME" ] ; then
	onexit "NOMINATIM_HOME=${NOMINATIM_HOME} directory does not exist"
fi
if [ ! -d "$BUILD_DIR" ] ; then
	onexit "BUILD_DIR=${BUILD_DIR} directory does not exist"
fi
if [ ! -f "$COUNTRY_LIST" ] ; then
	onexit "COUNTRY_LIST=${COUNTRY_LIST} file does not exist"
fi

acquire_lock
echo "Starting Nominatim data update at $(date)" >>"$OUT" 2>&1

### Foreach country check if configuration exists (if not create one) and then import the diff
while read -r COUNTRY; do
	DIR="${NOMINATIM_HOME}/updates/$COUNTRY"
    FILE="$DIR/configuration.txt"
    if [ ! -f ${FILE} ]; then
        sudo -u $USERNAME mkdir -p ${DIR} >>"$OUT" 2>&1
        echo "Running: osmosis --rrii workingDirectory=${DIR}/." >>"$OUT" 2>&1
        sudo -u $USERNAME osmosis --rrii workingDirectory=${DIR}/. >>"$OUT" 2>&1
        sudo -u $USERNAME echo "baseUrl=http://download.geofabrik.de/${COUNTRY}-updates" > ${FILE}
        sudo -u $USERNAME echo "maxInterval = 0" >> ${FILE}
        cd ${DIR}
        sudo -u $USERNAME wget -q "http://download.geofabrik.de/${COUNTRY}-updates/state.txt" >>"$OUT" 2>&1
        echo "$COUNTRY state.txt content:" >>"$OUT" 2>&1
        cat state.txt >>"$OUT" 2>&1
    fi
    FILENAME=${COUNTRY//[\/]/_}
    echo "Running: osmosis --rri workingDirectory=${DIR}/. --wxc ${FILENAME}.osc.gz" >>"$OUT" 2>&1
    sudo -u $USERNAME osmosis --rri workingDirectory=${DIR}/. --wxc ${FILENAME}.osc.gz >>"$OUT" 2>&1
    if [ $? -ne 0 ] ; then
		onexit "osmosis failed for $COUNTRY"
    fi
done < "$COUNTRY_LIST"

INDEX=0 # false

cd "$BUILD_DIR"
echo "Entered build directory: $BUILD_DIR" >>"$OUT" 2>&1
ls -al >>"$OUT" 2>&1

### Foreach diff files do the import
for OSC in *.osc.gz; do
	echo "Running: $UPDATE_PHP --import-diff updates/${OSC} --no-npi" >>"$OUT" 2>&1
    sudo -u $USERNAME "$UPDATE_PHP" --import-diff ${NOMINATIM_HOME}/updates/${OSC} --no-npi >>"$OUT" 2>&1
	if [ $? -ne 0 ] ; then
		onexit "$UPDATE_PHP failed for ${OSC}"
    fi
    INDEX=1
done

### Re-index if needed
if ((${INDEX})); then
	echo "Re-indexing" >>"$OUT" 2>&1
    sudo -u $USERNAME "$UPDATE_PHP" --index >>"$OUT" 2>&1
	if [ $? -ne 0 ] ; then
		onexit "$UPDATE_PHP re-index failed"
    fi
fi

### Remove all diff files
sudo -u $USERNAME rm -f ${NOMINATIM}/updates/*.osc.gz >>"$OUT" 2>&1

onexit
