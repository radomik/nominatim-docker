Nominatim Docker container
==========================

## Introduction

This is modified version of following Nominatim docker containers:

- https://github.com/merlinnot/nominatim-docker
- https://github.com/peter-evans/nominatim-docker

Idea of this repository is to add ability of:
- importing multiple countries into Nominatim server
- run periodical updates on every configured country

## Development guide

### Build image
```shell
cd <project directory>
docker build . -t <tag_name>
```

### Import Nominatim data files

The following will create a new container, import PBF files and start Nominatim server configured with periodic updates enabled.

```shell
# Remember to place <tag_name> always at the end otherwise envirioment variables won't be passed
docker run -d -p 8089:8080 --user=root -e countries="europe/monaco europe/andorra europe/latvia" <tag_name>
```

Available environment parameters are:

|  Name |  Default value | Description |
|---|---|---|
| COUNTRIES | | List of space separated countries to be imported into Nominatim search engine |
| BUILD_MEMORY | 5 | Amount of memory in gigabytes used by Postgres database during Nominatim data initial import |
| BUILD_THREAD_COUNT | 8 | Thread count used by Postgres during Nominatim data import |
| RUNTIME_THREAD_COUNT | 4 | Thread count used by Postgres at Nominatim runtime |
| RUNTIME_MEMORY | 4 | Amount of memory in gigabytes used by Postgres database at runtime |
| UPDATE_CRON_SETTINGS | 40 4 * * * | Crontab setting for Nominatim data update cron job (See https://crontab.guru/) |
| CRON_LOG_LEVEL | 0 | Cron log level (see: `man cron`) |

It may be useful to see logs directly after running container:
```shell
docker container logs -f <container ID>
```

### Access Nominatim:
- http://127.0.0.1:8089
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=html
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=jsonv2

### Commands useful while testing

```shell
# Stop running container
~/projects/radomik-nominatim-docker (master) $ docker container ls
CONTAINER ID        IMAGE                       COMMAND                  CREATED              STATUS              PORTS                    NAMES
cddc5607af74        symmetra/nominatim-docker   "/srv/nominatim/util…"   About a minute ago   Up About a minute   0.0.0.0:8089->8080/tcp   happy_mestorf

# Remove all containers
~/projects/radomik-nominatim-docker (master) $ docker rm $(docker ps -a -q)

# Optional - remove image
~/projects/radomik-nominatim-docker (master) $ docker images
REPOSITORY                  TAG                 IMAGE ID            CREATED             SIZE
symmetra/nominatim-docker   latest              94904d9b4847        2 minutes ago       1.62GB

~/projects/radomik-nominatim-docker (master) $ docker rmi 94904d9b4847

# Build new image
~/projects/radomik-nominatim-docker (master) $ docker build . -t symmetra/nominatim-docker

# Import data and setup container (data update every minute) & show logs of above command
## Dell M6600
docker run -d -p 8090:8080 --user=root --restart=always -e COUNTRIES="europe/monaco europe/andorra europe/switzerland" -e UPDATE_CRON_SETTINGS="*/60 * * * *" -e BUILD_MEMORY=20 -e BUILD_THREADS=12 -e RUNTIME_MEMORY=10 -e RUNTIME_THREADS=3 symmetra/nominatim-docker
97329f4b643c9660d28d62df0bafbe733f7f33f44e0b9f434afde57d64bbedb4
## Virtualbox
docker run -d -p 8090:8080 --user=root --restart=always -e COUNTRIES="europe/monaco europe/andorra" -e UPDATE_CRON_SETTINGS="*/60 * * * *" -e BUILD_MEMORY=6 -e BUILD_THREADS=4 -e RUNTIME_MEMORY=4 -e RUNTIME_THREADS=2 symmetra/nominatim-docker
97329f4b643c9660d28d62df0bafbe733f7f33f44e0b9f434afde57d64bbedb4

~/projects/radomik-nominatim-docker (master) $ docker container logs -f 97329f4b643c9660d28d62df0bafbe733f7f33f44e0b9f434afde57d64bbedb4

# After above command is finished:
~ $ docker container ls
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS                    NAMES
cddc5607af74        symmetra/nominatim-docker   "/srv/nominatim/util…"   7 minutes ago       Up 7 minutes        0.0.0.0:8089->8080/tcp   happy_mestorf

## Show syslog
docker exec -it --user=root cddc5607af74 cat /var/log/syslog

## Show Nominatim update log
docker exec -it --user=root cddc5607af74 cat /var/log/nominatim-update.log
```

---
### (internal) build image and push to dockerhub

```shell
# make sure Symmetra repository is up-to-date with this repository
git remote add symmetra git@github.com:Symmetra/nominatim-docker.git
git push symmetra master

# Build image locally 
cd <project directory>
docker build . -t symmetra/nominatim-docker

# List images
docker images
	REPOSITORY                            TAG                 IMAGE ID            CREATED             SIZE
	symmetra/nominatim-docker             latest              1887d6dd5680        7 seconds ago       1.56GB

# Login to dockerhub (as: dariuszmikolajczuk)
docker login

# Push the image to dockerhub: https://hub.docker.com/r/symmetra/nominatim-docker/
docker push symmetra/nominatim-docker
```

