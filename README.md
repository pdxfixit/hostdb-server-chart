# Hostdb-server Helm chart

This repo contains the Kubernetes Helm chart for [hostdb-server](https://github.com/pdxfixit/hostdb-server) and the collectors; [AWS](https://github.com/pdxfixit/hostdb-collector-aws), [OneView](https://github.com/pdxfixit/hostdb-collector-oneview), [OpenStack](https://github.com/pdxfixit/hostdb-collector-openstack), [UCS](https://github.com/pdxfixit/hostdb-collector-ucs) and [vROps](https://github.com/pdxfixit/hostdb-collector-vrops).

## Prerequisites

Please ensure the following apps are installed.

* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [Helm 3](https://helm.sh/docs/intro/install/#from-the-binary-releases)

In addition, please ensure you have a valid [kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/), in order to manage the Kubernetes cluster.

## Usage

Once a database instance is ready for use, let's launch the HostDB app.
First, we start with some secrets.

### Create secrets

#### TLS

Create a secret named `hostdb-tls`, by placing hostdb.crt.pem and hostdb.key.pem files into the project folder and running `make ssl`. 
Generating the certificate is not discussed here.
Creating the kubernetes secret can be accomplished like so:

```shell script
$ make ssl CRT=`pwd`/other.crt.pem KEY=`pwd`/other.crt.pem
```

When downloading a new certificate, please choose the `PKCS #12` format, and provide a password of your choosing.

Once the bag is downloaded, replace the existing kubernetes TLS secret by running the following command.
You'll be prompted (twice) for the password provided in the previous step.

```shell script
$ make replace_ssl PFX=hostdb.pfx
```

#### Collectors

Create secrets for all the collector cron jobs.
They can also be created individually if required.
(e.g. `make ucs_creds UCS_PASSWORD="soopersekret"`)

```shell script
$ make collector_creds AWS_ACCESS_KEY_ID="id" AWS_SECRET_ACCESS_KEY="sekret" ONEVIEW_PASSWORD="sekret" OPENSTACK_PASSWORD="sekret" UCS_PASSWORD="sekret" VROPS_PASSWORD="sekret"
```

#### Database

Create a secret named `hostdb-server-db`, with an existing database credential pair.

```shell script
$ make db_creds DB_USERNAME="app" DB_PASSWORD="sekret"
```

#### App

Create a secret named `hostdb-server-admin`, which contains a password used for HostDB admin and write operations.

```shell script
$ make password ADMIN_PASSWORD="soopersekret"
```

### Launch HostDB

Once the secrets are created, install the chart.

```shell script
$ make install
```

### Check the HostDB logs

Next, let's check the stderr output from the HostDB app container, and ensure the service is ok.

```shell script
$ make k8s_logs
```

## Upgrades

HostDB gets upgraded by an [automated deploy job](https://builds.pdxfixit.com/gh/hostdb-server).
Only passing builds in the [`hostdb-server` main branch](https://github.com/pdxfixit/hostdb-server/tree/master) will be tagged as `latest` and deployed.

If a manual upgrade (or downgrade) is required, simply run `make upgrade tag=0.1.199` to upgrade HostDB to the container image tagged `0.1.199`.

## Testing

Create a new instance of HostDB with the following command:

```shell script
$ make everything NAMESPACE=hostdb-test AWS_ACCESS_KEY_ID="id" AWS_SECRET_ACCESS_KEY="sekret" ONEVIEW_PASSWORD="sekret" OPENSTACK_PASSWORD="sekret" UCS_PASSWORD="sekret" VROPS_PASSWORD="sekret" DB_USERNAME="app" DB_PASSWORD="badpassword" ADMIN_PASSWORD="anotherbadpassword"
```

And remove it with the following:

```shell script
$ make clean NAMESPACE=hostdb-test
```

## Debugging

There are also extra commands available in the Makefile;

* `k8s_describe` &ndash; have Kubernetes describe the HostDB pod
* `k8s_logs` &ndash; show the Kubernetes container logs for HostDB

## See Also

* https://github.com/pdxfixit/hostdb-server
* https://github.com/pdxfixit/hostdb-collector-aws
* https://github.com/pdxfixit/hostdb-collector-oneview
* https://github.com/pdxfixit/hostdb-collector-openstack
* https://github.com/pdxfixit/hostdb-collector-ucs
* https://github.com/pdxfixit/hostdb-collector-vrops
