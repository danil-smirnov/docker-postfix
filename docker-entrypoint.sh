#!/bin/bash

MAIL_DOMAIN=${MAIL_DOMAIN:=example.com}
MAIL_HOST=${MAIL_HOST:-$MAIL_DOMAIN}
SMTP_USER=${SMTP_USER:=user:password}
DKIM_SELECTOR=${DKIM_SELECTOR:=mail}
CRON_ENABLED=${LOGS_CLEANUP:=1}

# Supervisor

cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true
user=root
EOF

# Cron

if [[ "${CRON_ENABLED,,}" = "1" || "${CRON_ENABLED,,}" = "yes" || "${CRON_ENABLED,,}" = "true" ]]; then

cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF
[program:cron]
command=cron -f
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

rm -f /etc/cron.daily/*
rm -f /etc/cron.d/*

fi

# Postfix

cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF
[program:postfix]
command=/postfix.sh
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
[program:maillog2stdout]
command=tail -f /var/log/mail.log
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat > /postfix.sh <<'EOF'
#!/bin/bash
trap "postfix stop" SIGINT
trap "postfix stop" SIGTERM
trap "postfix reload" SIGHUP
postfix start
sleep 5
while kill -0 "$(cat /var/spool/postfix/pid/master.pid)"; do
  sleep 5
done
EOF

chmod +x /postfix.sh

postconf -e myhostname=${MAIL_HOST}
postconf -e myorigin=${MAIL_DOMAIN}

postconf -F '*/*/chroot = n'

echo "$MAIL_DOMAIN" > /etc/mailname

postconf -e "mydestination = \$myhostname, /etc/mailname, localhost, localhost.localdomain"

postconf -e maillog_file=/var/log/mail.log

echo '0 0 * * * root echo "" > /var/log/mail.log' > /etc/cron.d/maillog

# SASL

# /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination

# smtpd.conf
cat > /etc/postfix/sasl/smtpd.conf <<EOF
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

CRT_FILE=/etc/postfix/certs/${MAIL_HOST}.crt
KEY_FILE=/etc/postfix/certs/${MAIL_HOST}.key

if [[ -f "${CRT_FILE}" && -f "${KEY_FILE}" ]]; then

# /etc/postfix/main.cf
postconf -e smtpd_tls_cert_file=${CRT_FILE}
postconf -e smtpd_tls_key_file=${KEY_FILE}
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

KEY_FILES=$(find /etc/opendkim/domainkeys -iname *.private)
if [[ -n "${KEY_FILES}" ]]; then

cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF
[program:opendkim]
command=/usr/sbin/opendkim -f
[program:rsyslog]
command=/usr/sbin/rsyslogd -n
[program:syslog2stdout]
command=tail -f /var/log/syslog
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# /etc/postfix/main.cf
postconf -e milter_protocol=2
postconf -e milter_default_action=accept
postconf -e smtpd_milters=inet:localhost:12301
postconf -e non_smtpd_milters=inet:localhost:12301

cp -n /etc/opendkim.conf /etc/opendkim.conf.orig
cp /etc/opendkim.conf.orig /etc/opendkim.conf
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

cp -n /etc/default/opendkim /etc/default/opendkim.orig
cp /etc/default/opendkim.orig /etc/default/opendkim
cat >> /etc/default/opendkim <<EOF
SOCKET="inet:12301@localhost"
EOF

cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
${MAIL_DOMAIN}
EOF

DKIM_FILE=/etc/opendkim/domainkeys/${DKIM_SELECTOR}.private

cat > /etc/opendkim/KeyTable <<EOF
${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:${DKIM_SELECTOR}:${DKIM_FILE}
EOF

cat > /etc/opendkim/SigningTable <<EOF
*@${MAIL_DOMAIN} ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
EOF

for kf in ${KEY_FILES}; do
if [[ "${kf}" != "${DKIM_FILE}" ]]; then
kfn="${kf##*._domainkey.}"
DKIM_DOMAIN="${kfn%.private}"
kfs="${kf%%._domainkey.*}"
DKIM_SELECTOR="${kfs##*/}"
echo "${DKIM_DOMAIN}" >> /etc/opendkim/TrustedHosts
echo "${DKIM_SELECTOR}._domainkey.${DKIM_DOMAIN} ${DKIM_DOMAIN#\*.}:${DKIM_SELECTOR}:${kf}" >> /etc/opendkim/KeyTable
echo "*@${DKIM_DOMAIN} ${DKIM_SELECTOR}._domainkey.${DKIM_DOMAIN}" >> /etc/opendkim/SigningTable
fi
done

chown opendkim:opendkim /etc/opendkim/domainkeys
chmod 770 /etc/opendkim/domainkeys
chown opendkim:opendkim ${KEY_FILES}
chmod 400 ${KEY_FILES}

echo '0 0 * * * root echo "" > /var/log/syslog' > /etc/cron.d/syslog

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
EOF

echo '[Definition]
logtarget = STDOUT' > /etc/fail2ban/fail2ban.d/log2stdout.conf

echo '[postfix-sasl]
enabled = true' > /etc/fail2ban/jail.d/defaults-debian.conf

[[ -n "${FAIL2BAN_BANTIME}" ]] && echo "bantime = ${FAIL2BAN_BANTIME}" >> /etc/fail2ban/jail.d/defaults-debian.conf
[[ -n "${FAIL2BAN_FINDTIME}" ]] && echo "findtime = ${FAIL2BAN_FINDTIME}" >> /etc/fail2ban/jail.d/defaults-debian.conf
[[ -n "${FAIL2BAN_MAXRETRY}" ]] && echo "maxretry = ${FAIL2BAN_MAXRETRY}" >> /etc/fail2ban/jail.d/defaults-debian.conf

mkdir -p /run/fail2ban

echo '1 0 * * * root echo "Log truncated at $(date +\%s)" > /var/log/mail.log' > /etc/cron.d/maillog

fi

# Rsyslogd does not start fix

rm -f /var/run/rsyslogd.pid

# Custom configuration

[[ -f "/configure.sh" ]] && bash /configure.sh

exec "$@"
