FROM fedora:26
MAINTAINER Michal Karm Babacek <karm@redhat.com>

ENV DEPS            java-1.8.0-openjdk-devel.x86_64 unzip wget gawk sed
ENV CATALINA_HOME   /opt/tomcat/jws-3.1/tomcat8/
ENV TC_CONF_DIR     ${CATALINA_HOME}/conf/
ENV TC_WEBAPPS      ${CATALINA_HOME}/webapps/
ENV OPENSSL_CONF    ${CATALINA_HOME}/conf/openssl/pki/tls/openssl.cnf
ENV LD_LIBRARY_PATH ${CATALINA_HOME}/lib/:$LD_LIBRARY_PATH
ENV PATH            /opt/tomcat/jws-3.1/openssl/bin/:${CATALINA_HOME}/bin/:$PATH
ENV JAVA_HOME       /usr/lib/jvm/java-1.8.0/
ENV JWS_ZIP         jws-application-servers-3.1.0-RHEL7-x86_64.zip
ENV JWS_PATCH_ZIP   jws-application-servers-3.1.1-RHEL7-x86_64.zip

RUN dnf -y update && dnf -y install ${DEPS} && dnf clean all
RUN useradd -s /sbin/nologin tomcat && mkdir -p /opt/tomcat /opt/tomcat/certs && chown tomcat /opt/tomcat -R && chgrp tomcat /opt/tomcat -R && chmod ug+rwxs /opt/tomcat -R

WORKDIR /opt/tomcat

EXPOSE 8080/tcp
EXPOSE 8009/tcp
EXPOSE 8443/tcp
EXPOSE 8005/tcp

USER tomcat

#Download (or copy) and install JWS

ADD ["${JWS_ZIP}", "${JWS_PATCH_ZIP}", "/opt/tomcat/"]

RUN unzip ${JWS_ZIP} 'jws-3.1/tomcat8/*' -d . && \
    yes | unzip ${JWS_PATCH_ZIP} 'jws-3.1/tomcat8/*' -d . && \
    rm -rf ${JWS_ZIP} && rm -rf ${JWS_PATCH_ZIP}

ENV JAVA_OPTS="\
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

ADD server.xml ${TC_CONF_DIR}
ADD tomcat.sh /opt/tomcat/
CMD ["/opt/tomcat/tomcat.sh"]
