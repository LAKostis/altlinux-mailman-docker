# altlinux-docker-mailman

Simple Mailman 2.x [docker](http://www.docker.com) image with SMTP authentication and multiple domain support.

It also includes rsyslog to enable logging.

I took some ideas and code from [docker-postfix](https://github.com/juanluisbaptiste/docker-postfix) image.

### Build instructions

Clone this repo and then:

    cd altlinux-docker-mailman
    sudo docker build -t alt-mailman .

### How to run it

The following env variables need to be passed to the container:

* `SMTP_SERVER` Server address of the SMTP server to use (relay).
* `SERVER_HOSTNAME` Server hostname for the Postfix container. Emails will appear to come from the hostname's domain.
* `ADMIN_EMAIL` Email address of the person who should get root's mail.

The following env variable(s) are optional.
* `SMTP_HEADER_TAG` This will add a header for tracking messages upstream. Helpful for spam filters. Will appear as "RelayTag: ${SMTP_HEADER_TAG}" in the email headers.

* `SMTP_NETWORKS` Setting this will allow you to add additional, comma seperated, subnets to use the relay. Used like
    -e SMTP_NETWORKS='xxx.xxx.xxx.xxx/xx,xxx.xxx.xxx.xxx/xx'

* `SMTP_PORT` (Optional, Default value: 25) Port address of the SMTP server to use.
* `SASL_ENABLED` (Optional, Default is unset) Use SASL authentication on relay.
* `SMTP_USERNAME` SASL Username to authenticate with.
* `SMTP_PASSWORD` SASL Password of the SMTP user.

Mailman specific vars, all optional (see defaults):
* `MAILMAN_LANG` (Optional, Default value:ru) Default mailman language
* `MAILMAN_URL_HOST` (Optional, Default value: $SERVER_HOSTNAME) Mailman URL FQDN, specified if mailman exposed outside with another name.
* `MAILMAN_EMAIL_HOST` (Optional, Default value: $MAILMAN_URL_HOST) Mailman email FQDN, used in messaging
* `MAILMAN_URL_PATTERN` (Optional, Default value: https://%s/mailman/) Mailman URL pattern used in messaging
* `MAILMAN_DOMAINS` (Optional, Default value: $MAILMAN_URL_HOST) FQDN list to serve

`MAILMAN_DOMAINS` can be specified as a simple list:

    <domain1.com> <domain2.xyz>..<domainN.zzz>

Or as key:value list with custom email hosts:

    <domain1.com>:<email domain.com> <domain2.xyz>...<domainN.zzz>:<email domainY.yyy>

As you see, `<domain2.xyz>` doesn't have email custom url, so it will be used as email url.

To use this container from anywhere, the 25 port or the one specified by `SMTP_PORT` needs to be exposed to the docker host server:

    docker run -d --name alt-mailman -p "25:25"  \ 
           -e SMTP_SERVER=smtp.bar.com \
           -e SMTP_USERNAME=foo@bar.com \
           -e SMTP_PASSWORD=XXXXXXXX \
           -e SERVER_HOSTNAME=lists.example.com \
           alt-mailman
    
If you are going to use this container from other docker containers then it's better to just publish the port:

    docker run -d --name alt-mailman -P \
           -e SMTP_SERVER=smtp.bar.com \
           -e SMTP_USERNAME=foo@bar.com \
           -e SMTP_PASSWORD=XXXXXXXX \
           -e SERVER_HOSTNAME=internal.example.com \
           -e MAILMAN_DOMAINS='lists.example.com lists.example2.org:example3.net'
           alt-mailman

To see the email logs in real time:

    docker logs -f alt-mailman

### Debugging
If you need troubleshooting the container you can set the environment variable _DEBUG=yes_ for a more verbose output.
