*Draft for owner review.* A **container** is an ordinary process (or group of processes) that the kernel isolates with namespaces and limits with cgroups, started from an **image**: a read-only bundle of files. It is not a small virtual machine; it shares the host's kernel. On AlmaLinux and other Red Hat family systems the standard tool is **Podman**. It needs no always-running daemon, and it can run containers without root.

## Images and containers

An **image** is the template; a **container** is a running (or stopped) instance of it. Images come from a **registry** such as `quay.io` or `registry.access.redhat.com`, named `registry/namespace/name:tag`. A tag like `:9` picks a version. Prefer a specific tag over `latest` so a machine rebuilt next month matches the one built today.

```
podman pull quay.io/almalinux/almalinux:9     # download an image
podman images                                 # local images
podman run --rm quay.io/almalinux/almalinux:9 cat /etc/os-release   # run once, then remove
podman run -d --name demo -p 8080:80 IMAGE    # detached, publish host port 8080 to container port 80
podman ps -a                                  # all containers, running or not
podman logs demo                              # what it printed
podman exec -it demo /bin/sh                  # a shell inside a running container
podman stop demo && podman rm demo
```

Anything written inside a container disappears with it. Keep data with a **volume** or a bind mount: `-v /srv/data:/data:Z`. On SELinux systems the `:Z` suffix relabels the folder so the container may use it; without it you meet a permission-denied that `chmod` will not fix.

## Rootless and rootful

Run as an ordinary user and the container is *rootless*: root inside the container is an unprivileged user on the host, so a break-out has little to hold on to. Rootless containers cannot bind ports below 1024 unless that is configured, and their images live in the user's home folder. Use rootful containers when a task really needs it, and say why.

## Containers as services

A container that should survive a restart is a systemd service. The current method is a **Quadlet** file: a short declarative description that systemd turns into a service.

```
# /etc/containers/systemd/web.container
[Container]
Image=quay.io/almalinux/almalinux:9
ContainerName=web
Exec=sleep infinity
PublishPort=8080:80

[Service]
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```
sudo systemctl daemon-reload      # regenerate the service from the file
sudo systemctl start web.service
systemctl status web.service
journalctl -u web.service
```

When a containerised service will not start, treat it like any service: `systemctl status`, `journalctl -u`, then `podman logs` and `podman ps -a`. The usual causes are a wrong command, a missing image, a port already in use, a volume that does not exist or has the wrong SELinux label, and a container that exits immediately because its main process finished.

## Building images, briefly

A `Containerfile` lists the steps that build an image: a base (`FROM`), files copied in, commands run, and the command to start (`CMD`). `podman build -t name .` runs it. Keep images small and put nothing secret in them.

## Check yourself

1. What is the difference between an image and a container?
2. A container writes a file, then is removed and recreated. Where did the file go?
3. A container service fails on every start. Name the first three commands you run.
