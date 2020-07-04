#!/bin/bash

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
SMTP_USER=${SMTP_USER:=user:password}
DKIM_SELECTOR=${DKIM_SELECTOR:=mail}

# Supervisor

cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true
user=root
[program:postfix]
command=/opt/postfix.sh
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Postfix

echo "#!/bin/bash
postfix start-fg${FAIL2BAN:+ | tee -a /var/log/mail.log}" > /opt/postfix.sh
chmod +x /opt/postfix.sh

postconf -e myhostname=${MAIL_HOST}
postconf -e myorigin=${MAIL_DOMAIN}

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
echo ${SMTP_USER} | tr , \\n > /tmp/passwd
while IFS=':' read -r _user _pwd; do
  echo $_pwd | saslpasswd2 -p -c -u ${MAIL_HOST} $_user
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
${MAIL_HOST}
*.${MAIL_DOMAIN}
EOF

cat >> /etc/opendkim/KeyTable <<EOF
${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:${DKIM_SELECTOR}:$(find /etc/opendkim/domainkeys -iname *.private)
EOF

cat >> /etc/opendkim/SigningTable <<EOF
*@${MAIL_DOMAIN} ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
EOF

chown :opendkim /etc/opendkim/domainkeys
chmod 770 /etc/opendkim/domainkeys
chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
chmod 400 $(find /etc/opendkim/domainkeys -iname *.private)

fi

# Fail2ban

if [[ -n "${FAIL2BAN}" ]]; then

cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF
[program:fail2ban]
command=fail2ban-server -f -x -v start
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
[program:cron]
command=cron -f
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

echo '[Definition]
logtarget = STDOUT' > /etc/fail2ban/fail2ban.d/log2stdout.conf

echo '[postfix-sasl]
enabled = true' > /etc/fail2ban/jail.d/defaults-debian.conf

[[ -n "${FAIL2BAN_BANTIME}" ]] && echo "bantime = ${FAIL2BAN_BANTIME}" >> /etc/fail2ban/jail.d/defaults-debian.conf
[[ -n "${FAIL2BAN_FINDTIME}" ]] && echo "findtime = ${FAIL2BAN_FINDTIME}" >> /etc/fail2ban/jail.d/defaults-debian.conf
[[ -n "${FAIL2BAN_MAXRETRY}" ]] && echo "maxretry = ${FAIL2BAN_MAXRETRY}" >> /etc/fail2ban/jail.d/defaults-debian.conf

mkdir -p /run/fail2ban

echo '0 0 * * * root echo "" > /var/log/mail.log' > /etc/cron.d/logrotate

fi

# Custom configuration

[[ -f "/configure.sh" ]] && bash /configure.sh

exec "$@"
