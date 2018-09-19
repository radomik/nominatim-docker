#!/bin/bash

if [ "$(whoami)" != "root" ] ; then
	echo "Script shall be run as root. Current user: $(whoami)"
	exit 1
fi

USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"
BUILD_DIR="${NOMINATIM_HOME}/build"
UPDATE_PHP="./utils/update.php"

### Foreach country check if configuration exists (if not create one) and then import the diff
while read -r COUNTRY; do
	DIR="${NOMINATIM_HOME}/updates/$COUNTRY"
    FILE="$DIR/configuration.txt"
    if [ ! -f ${FILE} ]; then
        sudo -u $USERNAME mkdir -p ${DIR}
        echo "Running: osmosis --rrii workingDirectory=${DIR}/." 
        sudo -u $USERNAME osmosis --rrii workingDirectory=${DIR}/.
        sudo -u $USERNAME echo "baseUrl=http://download.geofabrik.de/${COUNTRY}-updates" > ${FILE}
        sudo -u $USERNAME echo "maxInterval = 0" >> ${FILE}
        cd ${DIR}
        sudo -u $USERNAME wget -q "http://download.geofabrik.de/${COUNTRY}-updates/state.txt"
        echo "$COUNTRY state.txt content:"
        cat state.txt
    fi
    FILENAME=${COUNTRY//[\/]/_}
    echo "Running: osmosis --rri workingDirectory=${DIR}/. --wxc ${FILENAME}.osc.gz" 
    sudo -u $USERNAME osmosis --rri workingDirectory=${DIR}/. --wxc ${FILENAME}.osc.gz
done < "$COUNTRY_LIST"

INDEX=0 # false

cd "$BUILD_DIR"
ls -al

### Foreach diff files do the import
for OSC in *.osc.gz; do
	echo "Running: $UPDATE_PHP --import-diff updates/${OSC} --no-npi" 
    sudo -u $USERNAME "$UPDATE_PHP" --import-diff ${NOMINATIM_HOME}/updates/${OSC} --no-npi
    INDEX=1
    ls -al
done

### Re-index if needed
if ((${INDEX})); then
	echo "Re-indexing"
    sudo -u $USERNAME "$UPDATE_PHP" --index
    ls -al
fi

### Remove all diff files
sudo -u $USERNAME rm -f ${NOMINATIM}/updates/*.osc.gz
