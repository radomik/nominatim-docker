Nominatim Docker container
==========================

## Introduction

This is modified version of following Nominatim docker containers:

- https://github.com/merlinnot/nominatim-docker
- https://github.com/peter-evans/nominatim-docker

Idea of this repository is to add ability of:
- importing multiple countries *.PBF files
- run periodical updates on every configured country (not available yet)

## Usage Quide

For detailed usage guide see [merlinnot/nominatim-docker/README.md](https://github.com/merlinnot/nominatim-docker/blob/master/README.md)

### Quick guide

1. Clone this repository

2. Build image

```shell
cd <project directory>
# OSM2PGSQL_CACHE (in MB) shall be set to 75% of BUILD_MEMORY
docker build . \
  -t dm-nominatim-docker \
  --build-arg BUILD_THREADS=8 \
  --build-arg BUILD_MEMORY=24GB \
  --build-arg OSM2PGSQL_CACHE=18430 \
  --build-arg RUNTIME_THREADS=4 \
  --build-arg RUNTIME_MEMORY=8GB \
  --build-arg PBF_URL="http://download.geofabrik.de/europe/monaco-latest.osm.pbf http://download.geofabrik.de/europe/andorra-latest.osm.pbf" \
  --build-arg REPLICATION_URL="http://download.geofabrik.de/europe/monaco-updates http://download.geofabrik.de/europe/andorra-updates/"
```
3. Run image
```shell
docker run --restart=always -d -p 8089:8080 merlinnot-nominatim-docker
```
4. Access:
- http://127.0.0.1:8089
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=html
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=jsonv2

