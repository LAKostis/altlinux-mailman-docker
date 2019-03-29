FROM legionus/altlinux-initroot:x86_64

USER root

RUN \
 apt-get -y update;\
 apt-get -y install mailman mailman-nginx postfix spawn-fcgi fcgiwrap supervisor rsyslog-classic gosu jq;\
 apt-get -y clean;

RUN sed -i -e "s/^nodaemon=false/nodaemon=true/" /etc/supervisord.conf
RUN control postfix server
RUN echo 'NETWORKING="yes"' > /etc/sysconfig/network
RUN mkdir -p /var/lock/subsys

COPY --chown=root:root etc/*.conf /etc/
COPY --chown=root:mailman etc/mailman/*.py /etc/mailman/
COPY run.sh /
RUN chmod +x /run.sh
COPY --chown=root:root etc/supervisord.d/*.ini /etc/supervisord.d/

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 25

CMD ["/run.sh"]
