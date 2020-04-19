FROM ubuntu:bionic
MAINTAINER Danil Smirnov

RUN apt update && apt install -y supervisor rsyslog postfix sasl2-bin opendkim opendkim-tools \
    && rm -rf /var/lib/apt/lists/*

ADD install.sh /opt/install.sh

CMD /opt/install.sh && /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
