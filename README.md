docker-postfix
==============

Run postfix with SMTP authentication (sasldb) in a Docker container.  
TLS and OpenDKIM support is optional. Fail2ban can be enabled.

## Installation
1. Pull image

	```bash
	$ docker pull danilsmirnov/postfix
	```

## Usage
1. Create postfix container with smtp authentication

	```bash
	$ docker run -p 25:25 \
		-e MAIL_DOMAIN=example.com -e SMTP_USER=user:pwd \
		--name postfix -d danilsmirnov/postfix
	# Set multiple user credentials: -e SMTP_USER=user1:pwd1,user2:pwd2,...,userN:pwdN
	```

2. Set mail host defferent from mail domain

	```bash
	$ docker run -p 25:25 \
		-e MAIL_DOMAIN=example.com -e MAIL_HOST=mail.example.com -e SMTP_USER=user:pwd \
		--name postfix -d danilsmirnov/postfix
	```

3. Enable OpenDKIM: save your domain key ```mail.private``` in ```/path/to/domainkeys```

	```bash
	$ docker run -p 25:25 \
		-e MAIL_DOMAIN=example.com -e MAIL_HOST=mail.example.com -e SMTP_USER=user:pwd \
		-v /path/to/domainkeys:/etc/opendkim/domainkeys \
		--name postfix -d danilsmirnov/postfix
	# Set DKIM_SELECTOR variable if not okay with default "mail" selector
	```

4. Enable TLS(587): save your SSL certificates ```mail.example.com.key``` and ```mail.example.com.crt``` to  ```/path/to/certs```

	```bash
	$ docker run -p 587:587 \
		-e MAIL_DOMAIN=example.com -e MAIL_HOST=mail.example.com -e SMTP_USER=user:pwd \
		-v /path/to/certs:/etc/postfix/certs \
		--name postfix -d danilsmirnov/postfix
	```

5. Enable Fail2ban with ```postfix-sasl``` jail to ban brute-force attackers

	```bash
	$ docker run -p 25:25 \
		-e MAIL_DOMAIN=example.com -e MAIL_HOST=mail.example.com -e SMTP_USER=user:pwd \
		-e FAIL2BAN=enabled --cap-add NET_ADMIN \
		--name postfix -d danilsmirnov/postfix
	# Note: NET_ADMIN capability must be granted to the container
	# FAIL2BAN_BANTIME, FAIL2BAN_FINDTIME and FAIL2BAN_MAXRETRY could be set as well
	```

6. Add your custom configuration script ```/configure.sh```

	```bash
	$ docker run -p 25:25 \
		-e MAIL_DOMAIN=example.com -e MAIL_HOST=mail.example.com -e SMTP_USER=user:pwd \
		-v /path/to/script:/configure.sh \
		--name postfix -d danilsmirnov/postfix
	```
	E.g., add an alias to forward mail to:
	```bash
	postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
	echo "mailbox@${MAIL_DOMAIN} address@domain.com" > /etc/postfix/virtual
	postmap /etc/postfix/virtual
	```

## Note
+ Login credential should be set to (`username@mail.example.com`, `password`) in SMTP client
+ You can assign the port of MTA on the host machine to one other than 25 ([postfix how-to](http://www.postfix.org/MULTI_INSTANCE_README.html))
+ Read the reference below to find out how to generate domain keys and add public key to the domain's DNS records

## Reference
+ [Overview of changes and improvements](https://blog.smirnov.la/postfix-in-docker-5bf01e425a47)
+ [Postfix SASL Howto](http://www.postfix.org/SASL_README.html)
+ [How To Install and Configure DKIM with Postfix on Debian Wheezy](https://www.digitalocean.com/community/articles/how-to-install-and-configure-dkim-with-postfix-on-debian-wheezy)

## Credits
+ [catatnight](https://github.com/catatnight/docker-postfix)
