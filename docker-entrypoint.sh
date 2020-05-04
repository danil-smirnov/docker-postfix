#!/bin/bash

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
SMTP_USER=${SMTP_USER:=user:password}

# Supervisor

cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true
user=root
[program:postfix]
command=postfix start-fg
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Postfix

postconf -e myhostname=$MAIL_DOMAIN

postconf -F '*/*/chroot = n'

echo "$MAIL_DOMAIN" > /etc/mailname

postconf -e maillog_file=/dev/stdout

# SASL

# /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination

# smtpd.conf
cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

# sasldb2
echo $SMTP_USER | tr , \\n > /tmp/passwd
while IFS=':' read -r _user _pwd; do
  echo $_pwd | saslpasswd2 -p -c -u $MAIL_DOMAIN $_user
done < /tmp/passwd
chown postfix.sasl /etc/sasldb2

# TLS

if [[ -n "$(find /etc/postfix/certs -iname *.crt)" && -n "$(find /etc/postfix/certs -iname *.key)" ]]; then

# /etc/postfix/main.cf
chmod 400 /etc/postfix/certs/*.*
postconf -e smtpd_tls_cert_file=$(find /etc/postfix/certs -iname *.crt)
postconf -e smtpd_tls_key_file=$(find /etc/postfix/certs -iname *.key)
postconf -e smtpd_tls_security_level=may
postconf -e smtp_tls_security_level=may

# /etc/postfix/master.cf
postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission"
postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination"

fi

# DKIM

if [[ -n "$(find /etc/opendkim/domainkeys -iname *.private)" ]]; then

cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF
[program:opendkim]
command=/usr/sbin/opendkim -f
EOF

# /etc/postfix/main.cf
postconf -e milter_protocol=2
postconf -e milter_default_action=accept
postconf -e smtpd_milters=inet:localhost:12301
postconf -e non_smtpd_milters=inet:localhost:12301

cat >> /etc/opendkim.conf <<EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           Yes
LogWhy                  Yes

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256

UserID                  opendkim:opendkim

Socket                  inet:12301@localhost
EOF

cat >> /etc/default/opendkim <<EOF
SOCKET="inet:12301@localhost"
EOF

cat >> /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
192.168.0.1/24

*.$MAIL_DOMAIN
EOF

cat >> /etc/opendkim/KeyTable <<EOF
mail._domainkey.$MAIL_DOMAIN $MAIL_DOMAIN:mail:$(find /etc/opendkim/domainkeys -iname *.private)
EOF

cat >> /etc/opendkim/SigningTable <<EOF
*@$MAIL_DOMAIN mail._domainkey.$MAIL_DOMAIN
EOF

chown :opendkim /etc/opendkim/domainkeys
chmod 770 /etc/opendkim/domainkeys
chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
chmod 400 $(find /etc/opendkim/domainkeys -iname *.private)

fi

# Custom configuration

[[ -f "/configure.sh" ]] && bash /configure.sh

exec "$@"
