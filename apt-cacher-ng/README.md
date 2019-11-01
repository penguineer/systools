# apt-cacher-ng in a Docker container

Easy to fix and controlled environment.

Taken from https://docs.docker.com/engine/examples/apt-cacher-ng/

## Motivation

apt-cacher-ng sometimes f*cks up its caches and has to be manually revived. Put it in a container so that fixing can by done be re-creating that container.

Caches are discarded when the container is rebuilt.

## Setup

* Deploy the docker container at a host reachable as `apt-proxy`.
* (Optional) Copy the file `01proxy` to `/etc/apt/conf.d`
* (Optional) Open port 3142 in the host's firewall

## Shell trail

Build:
```
docker build -t eg_apt_cacher_ng .
```

Run:
```
docker run -d -p 3142:3142 --restart always --name apt_cacher_ng eg_apt_cacher_ng
```

Show logs
```
docker logs -f apt_cacher_ng
```
