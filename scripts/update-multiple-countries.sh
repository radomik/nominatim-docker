#!/bin/bash

### Country list
COUNTRIES="europe/isle-of-man europe/kosovo"
NOMINATIM="/var/Nominatim"

### Foreach country check if configuration exists (if not create one) and then import the diff
for COUNTRY in $COUNTRIES;
do
    DIR="$NOMINATIM/updates/$COUNTRY"
    FILE="$DIR/configuration.txt"
    if [ ! -f ${FILE} ];
    then
        mkdir -p ${DIR}
        osmosis --rrii workingDirectory=${DIR}/.
        echo baseUrl=http://download.geofabrik.de/${COUNTRY}-updates > ${FILE}
        echo maxInterval = 0 >> ${FILE}
        cd ${DIR}
        wget http://download.geofabrik.de/${COUNTRY}-updates/state.txt
    fi
    FILENAME=${COUNTRY//[\/]/_}
    osmosis --rri workingDirectory=${DIR}/. --wxc ${FILENAME}.osc.gz
done

INDEX=0 # false

### Foreach diff files do the import
cd ${NOMINATIM}/updates
for OSC in *.osc.gz;
do
    ${NOMINATIM}/utils/update.php --import-diff ${NOMINATIM}/updates/${OSC} --no-npi
    INDEX=1
done

### Re-index if needed
if ((${INDEX}));
then
    ${NOMINATIM}/utils/update.php --index
fi

### Remove all diff files
rm -f ${NOMINATIM}/updates/*.osc.gz
