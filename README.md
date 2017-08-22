# jws-3-tomcat-8-mod_cluster

The purpose of this image is to run Tomcat 8 from [Red Hat JBoss Web Server 3 Application Server for RHEL 7 x86_64](https://access.redhat.com/jbossnetwork/restricted/listSoftware.html?downloadType=distributions&product=webserver&productChanged=yes), with [mod_cluster listener](http://modcluster.io/).


The download itself is hidden behind a registration-required wall, but once you have these zips in the directory alongside the Dockerfile:

 * jws-application-servers-3.1.0-RHEL7-x86_64.zip
 * jws-application-servers-3.1.1-RHEL7-x86_64.zip  (patch)

you can build the image and push it into you private or local registry.


Note that this image is a community testing and demonstration effort and it is not supported nor suitable for production deployment.

# Build the image

## With tag and push to your private registry

    docker build -t your-docker-registry.example.com/karm/jws-tomcat-8-mod_cluster:3.1.1 . && sudo docker push your-docker-registry.example.com/karm/jws-tomcat-8-mod_cluster:3.1.1

## With tag but only locally

    docker build -t jws-tomcat-8-mod_cluster:3.1.1 .

# Prepare your runtime configuration

The image is constructed so as it is fully configurable via environment properties. One could use these properties in a plain docker run command, docker-compose file or with an arbitrary Docker containers orchestration software.


For the full list of configurable properties, see [tomcat.sh](tomcat.sh), [server.xml](server.xml) and [tomcat-users.xml](tomcat-users.xml).


In this example, we use mod_cluster with full HTTPS configuration and HTTPS connector with full https configuration including ca certificate, client and server keys. Note that while HTTPS connector acts as a server and uses server certificate, mod_cluster listener actively initiates connections to the mod_proxy_balancer and thus acts as a client and uses client certificate.


One could disable HTTPS connector and disable HTTPS for mod_cluster listener, ```TOMCAT_MOD_CLUSTER_SSL=false```, ```TOMCAT_ENABLE_HTTPS_CONNECTOR=false```, and just start with AJP and/or HTTP connector: ```TOMCAT_ENABLE_HTTP_CONNECTOR=true```, ```OMCAT_ENABLE_AJP_CONNECTOR=true``` and no undermentioned certificate generation would be needed. Note that when AJP connector is present, mod_cluster selects it by default automatically.


We don't store any certificates in the image, all certificates are injected to the container at runtime as base64 encoded strings via environment properties.

## Generate your certificates

Note that this is just for demonstration and testing purposes. Do not rely on this how-to for your production environment.


In an arbitrary directory, ```mkdir private certs newcerts
touch ./index.txt
echo 20 > ./serial```, download [openssl.cnf](https://gist.github.com/Karm/f23b974d4992f87982d65253e282554f) and then:

#### Create CA

    openssl req -config openssl.cnf -new -x509 -extensions v3_ca -keyout private/myca.key -out certs/myca.crt -days 1825

#### Server CSR

    openssl req -config openssl.cnf -new -nodes -keyout private/server.key -out server.csr -days 1825

#### Server Cert

    openssl ca -config openssl.cnf -policy policy_anything -cert certs/myca.crt -keyfile private/myca.key -out certs/server.crt -infiles server.csr

#### Client CSR

    openssl req -config openssl.cnf -new -nodes -keyout private/client.key -out client.csr -days 1825

#### Client Cert

    openssl ca -config openssl.cnf -policy policy_anything -cert certs/myca.crt -keyfile private/myca.key -out certs/client.crt -infiles client.csr

### Encode your certs base64

    TOMCAT_CA_CRT_BASE64=`base64 -w0 certs/myca.crt`
    TOMCAT_CLIENT_CRT_BASE64=`base64 -w0 certs/client.crt`
    TOMCAT_CLIENT_KEY_BASE64=`base64 -w0 private/client.key`
    TOMCAT_SERVER_CRT_BASE64=`base64 -w0 certs/server.crt`
    TOMCAT_SERVER_KEY_BASE64=`base64 -w0 private/server.key`

# Run the container

The undermentioned example uses host's network; one might easily change that. Note NIC name and IP address prefix. It is useful to have these things configurable, especially when using container orchestration tools with network overlays.

Furthermore, note Tomcat management username and password. Again, there is no default baked into the image, it is injected at runtime via env variables.

Last but not least, mod_cluster is configured to listen to UDP datagrams coming from Apache HTTP Server's mod_proxy cluster UDP multicast advertisements. Mod_cluster listener in the Tomcat instance thus learns about proxy's address and registers to it as a worker node. If UDP multicast is unavailable to you, e.g. due to a specific network overlay, you might set: ```TOMCAT_MOD_CLUSTER_ADVERTISE=false``` and enumerate your Apache HTTP Server instances with mod_proxy_cluster modules in ```TOMCAT_MOD_CLUSTER_PROXY_LIST=your.httpd-1.example.com:6666,your.httpd-2.example.com:6666
```. You can then remove ```TOMCAT_MOD_CLUSTER_ADVERTISE_PORT``` and ```TOMCAT_MOD_CLUSTER_ADVERTISE_GROUPADDRESS``` env vars.

Note that the communication between workers (Tomcat containers) and the balancer (Apache HTTP Server containers) is bidirectional: Tomcat container must be able to actively initiate a connection to the httpd container and vice versa.

## Running our HTTPS-enabled example

    docker run --net=host \
    -e 'TOMCAT_KEYSTORE_PASS=tomcat' \
    -e 'TOMCAT_JVM_ROUTE=worker-1' \
    -e 'TOMCAT_ENABLE_MOD_CLUSTER=true' \
    -e 'TOMCAT_MOD_CLUSTER_ADVERTISE=true' \
    -e 'TOMCAT_USERNAME=tomcat' \
    -e 'TOMCAT_PASSWORD=tomcat' \
    -e 'TOMCAT_NIC=enp0s31f6' \
    -e 'TOMCAT_ADDR_PREFIX=10' \
    -e 'TOMCAT_MOD_CLUSTER_ADVERTISE_PORT=23364' \
    -e 'TOMCAT_MOD_CLUSTER_ADVERTISE_GROUPADDRESS=224.0.1.105' \
    -e 'TOMCAT_ENABLE_HTTP_CONNECTOR=false' \
    -e 'TOMCAT_ENABLE_AJP_CONNECTOR=false' \
    -e 'TOMCAT_MOD_CLUSTER_SSL=true' \
    -e 'TOMCAT_ENABLE_HTTPS_CONNECTOR=true' \
    -e 'TOMCAT_HTTPS_CONNECTOR_CLIENT_AUTH=true' \
    -e 'TOMCAT_CA_CRT_BASE64=LS0tLS...many...more...chars...EUtLS0tLQo=' \
    -e 'TOMCAT_CLIENT_CRT_BASE64=Q2VydGlmaWNhd...many...more...chars...LS0tLS0K' \
    -e 'TOMCAT_CLIENT_KEY_BASE64=LS0tLS...many..more...chars...ktLS0tLQo=' \
    -e 'TOMCAT_SERVER_CRT_BASE64=Q2VydGlmaWN...many...more...chars...LRVktLS0tLQo=' \
    -d -i --name jws-tomcat-8-mod_cluster your-docker-registry.example.com/karm/jws-tomcat-8-mod_cluster:3.1.1



