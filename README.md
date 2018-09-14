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
docker build . -t dm-nominatim-docker
```

3. Run docker container for a built image
```shell
docker run --restart=always -d -p 8089:8080 dm-nominatim-docker
```

4. Import PBF files

Running this command second time will overwrite all existing Nominatim data.

Find out the name/ID of running docker container
```shell
docker container ls | grep dm-nominatim-docker
```

Import Nominatim data:
```shell
# OSM2PGSQL_CACHE (in MB) shall be set to 75% of BUILD_MEMORY
docker exec -it <container name/ID> /srv/nominatim/utils/init-pbf.sh \
	-p europe/monaco -p europe/andorra -p europe/latvia \ 
	-b 6 \
	-j 2 \
	-o 4500 \
	-t 4 \
	-r 2
```

Parameter description:
- `-p` - countries to be imported (one country per single `-p` option)
- `-b` - amount of memory in GB used by database during Nominatim data import
- `-o` - amount of memory in MB used by OSM2PGSQL cache (shall be 75% of value given in `-b` option)
- `-j` - amount of memory in GB used by database at runtime
- `-t` - thread count used during Nominatim data import
- `-r` - thread count used at runtime

5. Access Nominatim:
- http://127.0.0.1:8089
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=html
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=jsonv2

6. Run data update:
```shell
TODO
```
