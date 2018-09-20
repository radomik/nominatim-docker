Nominatim Docker container
==========================

## Introduction

This is modified version of following Nominatim docker containers:

- https://github.com/merlinnot/nominatim-docker
- https://github.com/peter-evans/nominatim-docker

Idea of this repository is to add ability of:
- importing multiple countries into Nominatim server
- run periodical updates on every configured country

### Quick guide

1. Clone this repository


2. Build image

```shell
cd <project directory>
docker build . -t <tag_name>
```

3. Import Nominatim data files

The following will create a new container, import PBF files and start Nominatim server configured with periodic updates enabled.

```shell
docker run -d -p 8089:8080 --user=root <tag_name> /srv/nominatim/utils/init-pbf.sh -p europe/monaco -p europe/andorra -p europe/latvia
docker run -d -p 8089:8080 --user=root <tag_name> /srv/nominatim/utils/init-pbf.sh -p europe/monaco
```

For parameter description and default values see:
```shell
docker run -p 8089:8080 --user=root <tag_name> /srv/nominatim/utils/init-pbf.sh --help
```

It may be useful to see logs directly after running container:
```shell
docker container logs -f <container ID>
```

4. Run data update (TODO: shall be a cron job)
```shell
docker exec -it --user=root <container ID> bash -x /srv/nominatim/utils/update.sh
```

5. Access Nominatim:
- http://127.0.0.1:8089
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=html
- http://127.0.0.1:8089/search?q=Monte-Carlo&format=jsonv2


---


## Build image and push to dockerhub

```shell
# Build image locally 
cd <project directory>
docker build . -t symmetra/nominatim-docker

# List images
docker images
	REPOSITORY                            TAG                 IMAGE ID            CREATED             SIZE
	symmetra/nominatim-docker   latest              1887d6dd5680        7 seconds ago       1.56GB

# Login to dockerhub (as: dariuszmikolajczuk)
docker login

# Push the image to dockerhub: https://hub.docker.com/r/symmetra/nominatim-docker/
docker push symmetra/nominatim-docker
```
