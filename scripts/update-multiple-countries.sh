#!/bin/bash
# Usage:
# ./update-multiple-countries.sh [<log file>]

DEFAULT_OUT="/dev/stdout"
OUT="$DEFAULT_OUT"
CUSTOM_OUT="$1"
USERNAME="nominatim"
NOMINATIM_HOME="/srv/nominatim"
UPDATES_DIR="${NOMINATIM_HOME}/updates"
COUNTRY_LIST="${NOMINATIM_HOME}/data/countries.txt"
BUILD_DIR="${NOMINATIM_HOME}/build"
UPDATE_PHP="./utils/update.php"
LOCKED=0
LOCK_DIR="/var/run/nominatim-update.lock"

function init_log {
  if [ ! -z "$CUSTOM_OUT" ] ; then
    OUT="$CUSTOM_OUT"
    if [ ! -f "$OUT" ] ; then
      touch "$OUT"
      chown "$USERNAME" "$OUT"
    fi
  fi
}

function release_lock {
	if ((${LOCKED})); then
		rmdir "$LOCK_DIR"
		LOCKED=0
	fi
}

function onexit {
	if [ ! -z "$1" ] ; then
		echo "[ERROR] $1" >>"$OUT" 2>&1
		if [ "$OUT" != "$DEFAULT_OUT" ] ; then
			echo "[ERROR] $1"
		fi
	else
		echo "[$$] Exiting successfully" >>"$OUT" 2>&1
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
		onexit "[$$] Update script already running"
	fi
}

function startup_checks {
  test "$(whoami)" == "root" || onexit "[$$] Script shall be run as root. Current user: $(whoami)"
  id -u "$USERNAME" >/dev/null 2>&1 || onexit "[$$] User '$USERNAME' does not exist"
  test -d "$NOMINATIM_HOME" || onexit "[$$] NOMINATIM_HOME=${NOMINATIM_HOME} directory does not exist"
  test -d "$BUILD_DIR" || onexit "[$$] BUILD_DIR=${BUILD_DIR} directory does not exist"
  test -f "$COUNTRY_LIST" || onexit "[$$] COUNTRY_LIST=${COUNTRY_LIST} file does not exist"
}

function run_cmd {
  local cmd="$*"
  echo "[$$] Running: $cmd" >>"$OUT" 2>&1
  $cmd >>"$OUT" 2>&1
  local retv="$?"
  test $retv -eq 0 || onexit "[$$] Command $cmd failed with status $retv"
}

init_log
acquire_lock
startup_checks

echo "[$$] Starting Nominatim data update at $(date)" >>"$OUT" 2>&1

### Foreach country check if configuration exists (if not create one) and then import the diff
while read -r COUNTRY; do
	COUNTRY_UPDATE_DIR="${UPDATES_DIR}/$COUNTRY"
  COUNTRY_CONFIG_FILE="${COUNTRY_UPDATE_DIR}/configuration.txt"
  if [ ! -f "$COUNTRY_CONFIG_FILE" ] ; then
      run_cmd sudo -u $USERNAME mkdir -p "$COUNTRY_UPDATE_DIR" >>"$OUT" 2>&1
      run_cmd sudo -u $USERNAME osmosis --rrii workingDirectory=${COUNTRY_UPDATE_DIR}/.

      sudo -u $USERNAME echo "baseUrl=http://download.geofabrik.de/${COUNTRY}-updates" > "$COUNTRY_CONFIG_FILE"
      sudo -u $USERNAME echo "maxInterval = 0" >> "$COUNTRY_CONFIG_FILE"
      cd "$COUNTRY_UPDATE_DIR"

      run_cmd sudo -u $USERNAME wget -q "http://download.geofabrik.de/${COUNTRY}-updates/state.txt" >>"$OUT" 2>&1
      echo "[$$] $COUNTRY state.txt content:" >>"$OUT" 2>&1
      cat state.txt >>"$OUT" 2>&1
  fi
  COUNTRY_OSC_FILENAME=${COUNTRY//[\/]/_}
  run_cmd sudo -u $USERNAME osmosis --rri workingDirectory=${COUNTRY_UPDATE_DIR}/. --wxc ${COUNTRY_OSC_FILENAME}.osc.gz
done < "$COUNTRY_LIST"

INDEX=0 # false

cd "$BUILD_DIR"
echo "[$$] Entered build directory: $BUILD_DIR" >>"$OUT" 2>&1

echo "[$$] $UPDATES_DIR content:" >>"$OUT" 2>&1
tree "$UPDATES_DIR" >>"$OUT" 2>&1

### Foreach diff files do the import
for OSC in $(find "$UPDATES_DIR" -type f -name *.osc.gz); do
  echo "[$$] Loading diff file $OSC" >>"$OUT" 2>&1
  run_cmd sudo -u $USERNAME "$UPDATE_PHP" --import-diff "$OSC" --no-npi
  INDEX=1
done

### Re-index if needed
if ((${INDEX})); then
  run_cmd sudo -u $USERNAME "$UPDATE_PHP" --index
fi

### Remove all diff files
find "$UPDATES_DIR" -type f -name *.osc.gz -exec rm -v {} \;

echo "[$$] Finished Nominatim data update at $(date)" >>"$OUT" 2>&1
onexit
