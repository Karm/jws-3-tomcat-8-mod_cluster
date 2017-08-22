#!/bin/bash

# @author Michal Karm Babacek <karm@redhat.com>

# Debug logging
echo "STAT: `networkctl status`" >> /opt/tomcat/ip.log
echo "STAT ${TOMCAT_NIC:-eth0}: `networkctl status ${TOMCAT_NIC:-eth0}`" >> /opt/tomcat/ip.log

# Wait n seconds for the interface to wake up
TIMEOUT=20
MYIP=""
while [[ "${MYIP}X" == "X" ]] && [[ "${TIMEOUT}" -gt 0 ]]; do
    echo "Loop ${TIMEOUT}" >> /opt/tomcat/ip.log
    MYIP="`networkctl status ${TOMCAT_NIC:-eth0} | awk '{if($1~/Address:/){printf($2);}}'`"
    export MYIP
    let TIMEOUT=$TIMEOUT-1
    if [[ "${MYIP}" == ${TOMCAT_ADDR_PREFIX:-10}* ]]; then
        break;
    else 
        MYIP=""
        sleep 1;
    fi
done
echo -e "MYIP: ${MYIP}\nMYNIC: ${TOMCAT_NIC:-eth0}" >> /opt/tomcat/ip.log
if [[ "${MYIP}X" == "X" ]]; then 
    echo "${TOMCAT_NIC:-eth0} Interface error. " >> /opt/tomcat/ip.log
    exit 1
fi

if [ "`echo \"${HOSTNAME}\" | wc -c`" -gt 24 ]; then
    echo "ERROR: HOSTNAME ${HOSTNAME} must be up to 24 characters long."
    exit 1
fi


# Do we need certificates?
if [[ "${TOMCAT_MOD_CLUSTER_SSL:-true}" == "true" ]] || [[ "${TOMCAT_ENABLE_HTTPS_CONNECTOR:-true}" == "true" ]]; then

    # Both mod_cluster listener and https connector need ca.crt
    if [[ "${TOMCAT_CA_CRT_BASE64}X" == "X" ]]; then
        echo "TOMCAT_CA_CRT_BASE64 must contain base64 encoded PEM certificate, but it was empty."
        exit 1
    fi
    echo ${TOMCAT_CA_CRT_BASE64} | base64 -d  > /opt/tomcat/certs/ca.crt
    if ! [[ -s /opt/tomcat/certs/ca.crt ]]; then
        echo "File /opt/tomcat/certs/ca.crt must not be empty."
        exit 1
    fi

    # In case of mod_cluster listener, we use JKS for storing the CA certificate
    # Furthermore, mod_cluster listener acts as client to the mod_proxy_cluster balancer, hence client certificate in JKS.
    if [[ "${TOMCAT_MOD_CLUSTER_SSL:-true}" == "true" ]]; then
        if [[ "${TOMCAT_KEYSTORE_PASS}X" == "X" ]]; then
            echo "TOMCAT_KEYSTORE_PASS must contain a string but was empty."
            exit 1
        fi
        yes | keytool -import -file /opt/tomcat/certs/ca.crt -keystore /opt/tomcat/certs/ca-cert.jks -storepass "${TOMCAT_KEYSTORE_PASS}"
        if ! [[ -s /opt/tomcat/certs/ca-cert.jks ]]; then
            echo "File /opt/tomcat/certs/ca-cert.jks must not be empty."
            exit 1
        fi
        if [[ "${TOMCAT_CLIENT_CRT_BASE64}X" == "X" ]]; then
            echo "TOMCAT_CLIENT_CRT_BASE64 must contain base64 encoded PEM certificate, but it was empty."
            exit 1
        fi
        if [[ "${TOMCAT_CLIENT_KEY_BASE64}X" == "X" ]]; then
            echo "TOMCAT_CLIENT_KEY_BASE64 must contain base64 encoded PEM certificate, but it was empty."
            exit 1
        fi
        echo ${TOMCAT_CLIENT_CRT_BASE64} | base64 -d > /opt/tomcat/certs/client.crt
        echo ${TOMCAT_CLIENT_KEY_BASE64} | base64 -d > /opt/tomcat/certs/client.key
        if ! [[ -s /opt/tomcat/certs/client.crt ]]; then
            echo "File /opt/tomcat/certs/client.crt must not be empty."
            exit 1
        fi
        if ! [[ -s /opt/tomcat/certs/client.key ]]; then
            echo "File /opt/tomcat/certs/client.key must not be empty."
            exit 1
        fi
        openssl pkcs12 -export -in /opt/tomcat/certs/client.crt -inkey /opt/tomcat/certs/client.key -out /opt/tomcat/certs/client.pfx -passout pass:"${TOMCAT_KEYSTORE_PASS}"
        echo -e "${TOMCAT_KEYSTORE_PASS}\n${TOMCAT_KEYSTORE_PASS}\n${TOMCAT_KEYSTORE_PASS}" | keytool -importkeystore -destkeystore /opt/tomcat/certs/client-cert-key.jks -destalias "${TOMCAT_MOD_CLUSTER_SSL_KEY_ALIAS:-tcclient}" -srckeystore /opt/tomcat/certs/client.pfx -srcstoretype PKCS12
        if ! [[ -s /opt/tomcat/certs/client-cert-key.jks  ]]; then
            echo "File /opt/tomcat/certs/client-cert-key.jks  must not be empty."
            exit 1
        fi
    fi

    # Server certificates for the https connector.
    if [[ "${TOMCAT_ENABLE_HTTPS_CONNECTOR:-true}" == "true" ]]; then
        if [[ "${TOMCAT_SERVER_CRT_BASE64}X" == "X" ]]; then
            echo "TOMCAT_SERVER_CRT_BASE64 must contain base64 encoded PEM certificate, but it was empty."
            exit 1
        fi
        if [[ "${TOMCAT_SERVER_KEY_BASE64}X" == "X" ]]; then
            echo "TOMCAT_SERVER_KEY_BASE64 must contain base64 encoded PEM certificate, but it was empty."
            exit 1
        fi
        echo ${TOMCAT_SERVER_CRT_BASE64} | base64 -d > /opt/tomcat/certs/server.crt
        echo ${TOMCAT_SERVER_KEY_BASE64} | base64 -d > /opt/tomcat/certs/server.key
        if ! [[ -s /opt/tomcat/certs/server.crt ]]; then
            echo "File /opt/tomcat/certs/server.crt must not be empty."
            exit 1
        fi
        if ! [[ -s /opt/tomcat/certs/server.key ]]; then
            echo "File /opt/tomcat/certs/server.key must not be empty."
            exit 1
        fi
        # JKS for server certificate key pair is not used, because we leverage native OpenSSL via APR and org.apache.coyote.http11.Http11AprProtocol
        #openssl pkcs12 -export -in /opt/tomcat/certs/server.crt -inkey /opt/tomcat/certs/server.key -out /opt/tomcat/certs/server.pfx -passout pass:"${TOMCAT_KEYSTORE_PASS}"
        #echo -e "${TOMCAT_KEYSTORE_PASS}\n${TOMCAT_KEYSTORE_PASS}\n${TOMCAT_KEYSTORE_PASS}" | keytool -importkeystore -destkeystore /opt/tomcat/certs/server-cert-key.jks -srckeystore /opt/tomcat/certs/server.pfx -srcstoretype PKCS12
        #if ! [[ -s /opt/tomcat/certs/server-cert-key.jks  ]]; then
        #    echo "File /opt/tomcat/certs/server-cert-key.jks  must not be empty."
        #    exit 1
        #fi
    fi
fi

# General Tomcat settings
sed -i "s~@TOMCAT_SHUTDOWN_PORT@~${TOMCAT_SHUTDOWN_PORT:-8005}~g" ${TC_CONF_DIR}/server.xml
sed -i "s~@TOMCAT_DEFAULT_HOST@~${TOMCAT_DEFAULT_HOST:-localhost}~g" ${TC_CONF_DIR}/server.xml
sed -i "s~@TOMCAT_JVM_ROUTE@~${TOMCAT_JVM_ROUTE:-${HOSTNAME}}~g" ${TC_CONF_DIR}/server.xml

# Mod_cluster listener
if [[ "${TOMCAT_ENABLE_MOD_CLUSTER:-true}" == "true" ]]; then
    sed -i "s~<\!--MOD_CLUSTER_LISTENER~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~MOD_CLUSTER_LISTENER-->~~g" ${TC_CONF_DIR}/server.xml

    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL@~${TOMCAT_MOD_CLUSTER_SSL:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_TRUSTSTORE@~${TOMCAT_MOD_CLUSTER_SSL_TRUSTSTORE:-/opt/tomcat/certs/ca-cert.jks}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_TRUSTSTORE_PASSWORD@~${TOMCAT_KEYSTORE_PASS:-changeit}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_KEYSTORE@~${TOMCAT_MOD_CLUSTER_SSL_KEYSTORE:-/opt/tomcat/certs/client-cert-key.jks}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_KEYSTORE_PASSWORD@~${TOMCAT_KEYSTORE_PASS:-changeit}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_KEYSTORE_TYPE@~${TOMCAT_MOD_CLUSTER_SSL_KEYSTORE_TYPE:-JKS}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_TRUSTSTORE_TYPE@~${TOMCAT_MOD_CLUSTER_SSL_TRUSTSTORE_TYPE:-JKS}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_KEY_ALIAS@~${TOMCAT_MOD_CLUSTER_SSL_KEY_ALIAS:-tcclient}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_SSL_PROTOCOL@~${TOMCAT_MOD_CLUSTER_SSL_PROTOCOL:-TLSv1.2}~g" ${TC_CONF_DIR}/server.xml

    sed -i "s~@TOMCAT_MOD_CLUSTER_STICKY_SESSION_FORCE@~${TOMCAT_MOD_CLUSTER_STICKY_SESSION_FORCE:-false}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_STICKY_SESSION@~${TOMCAT_MOD_CLUSTER_STICKY_SESSION:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_STICKY_SESSION_REMOVE@~${TOMCAT_MOD_CLUSTER_STICKY_SESSION_REMOVE:-true}~g" ${TC_CONF_DIR}/server.xml

    sed -i "s~@TOMCAT_MOD_CLUSTER_LOAD_METRIC_CLASS@~${TOMCAT_MOD_CLUSTER_LOAD_METRIC_CLASS:-org.jboss.modcluster.load.metric.impl.BusyConnectorsLoadMetric}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_LOAD_METRIC_CAPACITY@~${TOMCAT_MOD_CLUSTER_LOAD_METRIC_CAPACITY:-1}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_LOAD_DECAY_FACTOR@~${TOMCAT_MOD_CLUSTER_LOAD_DECAY_FACTOR:-2}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_LOAD_HISTORY@~${TOMCAT_MOD_CLUSTER_LOAD_HISTORY:-9}~g" ${TC_CONF_DIR}/server.xml

    sed -i "s~@TOMCAT_MOD_CLUSTER_ADVERTISE@~${TOMCAT_MOD_CLUSTER_ADVERTISE:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_PROXY_LIST@~${TOMCAT_MOD_CLUSTER_PROXY_LIST:-""}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_ADVERTISE_PORT@~${TOMCAT_MOD_CLUSTER_ADVERTISE_PORT:-23364}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_ADVERTISE_INTERFACE@~${TOMCAT_MOD_CLUSTER_ADVERTISE_INTERFACE:-${TOMCAT_CONNECTOR_ADDRESS:-${MYIP}}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_MOD_CLUSTER_ADVERTISE_GROUPADDRESS@~${TOMCAT_MOD_CLUSTER_ADVERTISE_GROUPADDRESS:-224.0.1.105}~g" ${TC_CONF_DIR}/server.xml
fi

if [[ "${TOMCAT_ENABLE_HTTPS_CONNECTOR:-true}" == "true" ]]; then
    sed -i "s~<\!--HTTPS_CONNECTOR~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~HTTPS_CONNECTOR-->~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_PORT@~${TOMCAT_HTTPS_CONNECTOR_PORT:-8443}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_ADDRESS@~${TOMCAT_HTTPS_CONNECTOR_ADDRESS:-${TOMCAT_CONNECTOR_ADDRESS:-${MYIP}}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_PROTOCOL@~${TOMCAT_HTTPS_CONNECTOR_PROTOCOL:-org.apache.coyote.http11.Http11AprProtocol}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_ENABLED@~${TOMCAT_HTTPS_CONNECTOR_SSL_ENABLED:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_MAX_THREADS@~${TOMCAT_HTTPS_CONNECTOR_MAX_THREADS:-${TOMCAT_MAX_THREADS:-150}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SCHEME@~${TOMCAT_HTTPS_CONNECTOR_SCHEME:-https}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SECURE@~${TOMCAT_HTTPS_CONNECTOR_SECURE:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_CLIENT_AUTH@~${TOMCAT_HTTPS_CONNECTOR_CLIENT_AUTH:-true}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_FILE@~${TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_FILE:-/opt/workspace/server.crt}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_KEYFILE@~${TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_KEYFILE:-/opt/workspace/server.key}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_CHAINFILE@~${TOMCAT_HTTPS_CONNECTOR_SSL_CERTIFICATE_CHAINFILE:-/opt/workspace/ca.crt}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_PASSWORD@~${TOMCAT_KEYSTORE_PASS:-changeit}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_SSL_PROTOCOL@~${TOMCAT_HTTPS_CONNECTOR_SSL_PROTOCOL:-TLSv1.2}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_BUFFER_SIZE@~${TOMCAT_HTTPS_CONNECTOR_BUFFER_SIZE:-${TOMCAT_BUFFER_SIZE:-10240}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_COMPRESSION@~${TOMCAT_HTTPS_CONNECTOR_COMPRESSION:-${TOMCAT_COMPRESSION:-on}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_MAX_HTTP_HEADER_SIZE@~${TOMCAT_HTTPS_CONNECTOR_MAX_HTTP_HEADER_SIZE:-${TOMCAT_MAX_HTTP_HEADER_SIZE:-8192}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_CONNECTION_TIMEOUT@~${TOMCAT_HTTPS_CONNECTOR_CONNECTION_TIMEOUT:-${TOMCAT_CONNECTION_TIMEOUT:-20000}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_TCP_NO_DELAY@~${TOMCAT_HTTPS_CONNECTOR_TCP_NO_DELAY:-${TOMCAT_TCP_NO_DELAY:-true}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTPS_CONNECTOR_ENABLE_LOOKUPS@~${TOMCAT_HTTPS_CONNECTOR_ENABLE_LOOKUPS:-${TOMCAT_ENABLE_LOOKUPS:-true}}~g" ${TC_CONF_DIR}/server.xml
fi

if [[ "${TOMCAT_ENABLE_HTTP_CONNECTOR:-true}" == "true" ]]; then
    sed -i "s~<\!--HTTP_CONNECTOR~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~HTTP_CONNECTOR-->~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_PORT@~${TOMCAT_HTTP_CONNECTOR_PORT:-8080}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_ADDRESS@~${TOMCAT_HTTP_CONNECTOR_ADDRESS:-${TOMCAT_CONNECTOR_ADDRESS:-${MYIP}}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_PROTOCOL@~${TOMCAT_HTTP_CONNECTOR_PROTOCOL:-org.apache.coyote.http11.Http11AprProtocol}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_MAX_THREADS@~${TOMCAT_HTTP_CONNECTOR_MAX_THREADS:-${TOMCAT_MAX_THREADS:-150}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_BUFFER_SIZE@~${TOMCAT_HTTP_CONNECTOR_BUFFER_SIZE:-${TOMCAT_BUFFER_SIZE:-10240}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_COMPRESSION@~${TOMCAT_HTTP_CONNECTOR_COMPRESSION:-${TOMCAT_COMPRESSION:-on}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_MAX_HTTP_HEADER_SIZE@~${TOMCAT_HTTP_CONNECTOR_MAX_HTTP_HEADER_SIZE:-${TOMCAT_MAX_HTTP_HEADER_SIZE:-8192}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_CONNECTION_TIMEOUT@~${TOMCAT_HTTP_CONNECTOR_CONNECTION_TIMEOUT:-${TOMCAT_CONNECTION_TIMEOUT:-20000}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_TCP_NO_DELAY@~${TOMCAT_HTTP_CONNECTOR_TCP_NO_DELAY:-${TOMCAT_TCP_NO_DELAY:-true}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_ENABLE_LOOKUPS@~${TOMCAT_HTTP_CONNECTOR_ENABLE_LOOKUPS:-${TOMCAT_ENABLE_LOOKUPS:-true}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_HTTP_CONNECTOR_REDIRECT_PORT@~${TOMCAT_HTTP_CONNECTOR_REDIRECT_PORT:-${TOMCAT_HTTPS_CONNECTOR_PORT:-8443}}~g" ${TC_CONF_DIR}/server.xml
fi

if [[ "${TOMCAT_ENABLE_AJP_CONNECTOR:-true}" == "true" ]]; then
    sed -i "s~<\!--AJP_CONNECTOR~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~AJP_CONNECTOR-->~~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_PORT@~${TOMCAT_AJP_CONNECTOR_PORT:-8009}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_ADDRESS@~${TOMCAT_AJP_CONNECTOR_ADDRESS:-${TOMCAT_CONNECTOR_ADDRESS:-${MYIP}}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_PROTOCOL@~${TOMCAT_AJP_CONNECTOR_PROTOCOL:-org.apache.coyote.ajp.AjpAprProtocol}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_REDIRECT_PORT@~${TOMCAT_AJP_CONNECTOR_REDIRECT_PORT:-${TOMCAT_HTTPS_CONNECTOR_PORT:-8443}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_MAX_THREADS@~${TOMCAT_AJP_CONNECTOR_MAX_THREADS:-${TOMCAT_MAX_THREADS:-150}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_BUFFER_SIZE@~${TOMCAT_AJP_CONNECTOR_BUFFER_SIZE:-${TOMCAT_BUFFER_SIZE:-10240}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_MAX_HTTP_HEADER_SIZE@~${TOMCAT_AJP_CONNECTOR_MAX_HTTP_HEADER_SIZE:-${TOMCAT_MAX_HTTP_HEADER_SIZE:-8192}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_TCP_NO_DELAY@~${TOMCAT_AJP_CONNECTOR_TCP_NO_DELAY:-${TOMCAT_TCP_NO_DELAY:-true}}~g" ${TC_CONF_DIR}/server.xml
    sed -i "s~@TOMCAT_AJP_CONNECTOR_ENABLE_LOOKUPS@~${TOMCAT_AJP_CONNECTOR_ENABLE_LOOKUPS:-${TOMCAT_ENABLE_LOOKUPS:-true}}~g" ${TC_CONF_DIR}/server.xml
    # Note the meaning of connection timeout for HTTP-like and for AJP connectors is different, hence no TOMCAT_CONNECTION_TIMEOUT variable.
    sed -i "s~@TOMCAT_AJP_CONNECTOR_CONNECTION_TIMEOUT@~${TOMCAT_AJP_CONNECTOR_CONNECTION_TIMEOUT:-300000}~g" ${TC_CONF_DIR}/server.xml
fi

# tomcat-users.xml
if [[ "${TOMCAT_USERNAME}X" == "X" ]] || [[ "${TOMCAT_PASSWORD}X" == "X" ]]; then
    echo "Both TOMCAT_USERNAME and TOMCAT_PASSWORD must be set. There is no default password."
    exit 1
fi
sed -i "s~@TOMCAT_USERNAME@~${TOMCAT_USERNAME}~g" ${TC_CONF_DIR}/tomcat-users.xml
sed -i "s~@TOMCAT_PASSWORD@~${TOMCAT_PASSWORD}~g" ${TC_CONF_DIR}/tomcat-users.xml

export JAVA_OPTS="\
 -server \
 -Xms${TOMCAT_MS_RAM:-512m} \
 -Xmx${TOMCAT_MX_RAM:-512m} \
 -XX:MetaspaceSize=${TOMCAT_META_SPACE_SIZE:-64M} \
 -XX:MaxMetaspaceSize=${TOMCAT_MAX_META_SPACE_SIZE:-128m} \
 -XX:${TOMCAT_GC_IMPLEMENTATION:-+UseG1GC} \
 -XX:MaxGCPauseMillis=${TOMCAT_MAX_GC_PAUSE_MILLIS:-100} \
 -XX:InitiatingHeapOccupancyPercent=${TOMCAT_INITIATING_HEAP_OCCUPANCY_PERCENT:-70} \
 -XX:+HeapDumpOnOutOfMemoryError \
 -XX:HeapDumpPath=/opt/tomcat \
 -Djava.net.preferIPv4Stack=${TOMCAT_PREFER_IPV4_STACK:-true} \
 -Djava.awt.headless=true \
 -Djava.security.egd=${TOMCAT_RNG:-file:///dev/random}"

${CATALINA_HOME}/bin/catalina.sh run
