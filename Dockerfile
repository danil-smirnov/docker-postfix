FROM ubuntu:focal
MAINTAINER Danil Smirnov <danil@smirnov.la>

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y supervisor postfix sasl2-bin opendkim opendkim-tools iptables fail2ban cron rsyslog \
    && rm -rf /var/lib/apt/lists/*

COPY ./docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/usr/bin/supervisord"]
