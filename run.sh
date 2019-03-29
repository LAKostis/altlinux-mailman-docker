#!/bin/bash

[ "${DEBUG}" == "yes" ] && set -x

function add_config_value() {
  local key=${1}
  local value=${2}
  local config_file=${3:-/etc/postfix/main.cf}
  [ "${key}" == "" ] && echo "ERROR: No key set !!" && exit 1
  [ "${value}" == "" ] && echo "ERROR: No value set !!" && exit 1

  echo "Setting configuration option ${key} with value: ${value}"
 postconf -e "${key} = ${value}"
}

# mailman domains can be defined as <domain>:<mail url> or just <domain>
function format_domains() {
  local mode=${1}; shift
  local string=${1}
  local domains=
  local emails=
  for d in $string; do
    domain=${d%%:*}
    [ -n "$domain" ] && domains="$domains $domain,"
  done
  [ -n "$domains" ] && \
    domains="$(printf '%s' $domains| sed -rn -e 's/^ //;s/,$//p')" || exit 1
  case $mode in
    postfix)
      printf '%s\n' "$domains"
      ;;
    mailman)
      echo -n 'POSTFIX_STYLE_VIRTUAL_DOMAINS = '
      printf '%s' "$domains"|jq -sR 'split(",")'
      echo
      for d in $string; do
        domain=${d%%:*}
        email=${d#*:}
        [ -n "$email" -a "$email" != "$domain" ] || email=$domain
        printf "add_virtualhost('%s', '%s')\n" $domain $email
      done
      ;;
      *)
      echo 'wrong format'
      exit 1
      ;;
  esac
}

if [ -n "${SMTP_SERVER}" -a -n "${SERVER_HOSTNAME}" -a -n "${ADMIN_EMAIL}" ]; then
  echo "SMTP_SERVER=${SMTP_SERVER} SERVER_HOSTNAME=${SERVER_HOSTNAME} ADMIN_EMAIL=${ADMIN_EMAIL}"
else
  echo "SMTP_SERVER SERVER_HOSTNAME ADMIN_EMAIL all should be set!"
  exit 1
fi

if [ -n "${SASL_ENABLED}" ]; then
  if [ -n "${SMTP_USERNAME}" -a -n "${SMTP_PASSWORD}" ]; then
    add_config_value "smtp_sasl_auth_enable" "yes"
    add_config_value "smtp_sasl_password_maps" "cdb:/etc/postfix/sasl_passwd"
    add_config_value "smtp_sasl_security_options" "noanonymous"
  else
    echo "SMTP_USERNAME and SMTP_PASSWORD are not set"
    exit 1
  fi
fi

SMTP_PORT="${SMTP_PORT-25}"

# Get domain from the server host name
DOMAIN="${SERVER_HOSTNAME#*.}"
if [ -n "$DOMAIN" -a "$DOMAIN" == "$SERVER_HOSTNAME" ]; then
   echo "$SERVER_HOSTNAME is not FQDN!"
   exit 1
fi

# Set needed config options
add_config_value "myhostname" ${SERVER_HOSTNAME}
add_config_value "mydomain" ${DOMAIN}
add_config_value "mydestination" '$myhostname'
add_config_value "myorigin" '$mydomain'
add_config_value "relayhost" "[${SMTP_SERVER}]:${SMTP_PORT}"
add_config_value "smtp_use_tls" "yes"

# Create sasl_passwd file with auth credentials
if [ ! -f /etc/postfix/sasl_passwd ]; then
  grep -q "${SMTP_SERVER}" /etc/postfix/sasl_passwd  > /dev/null 2>&1
  if [ $? -gt 0 ]; then
    echo "Adding SASL authentication configuration"
    echo "[${SMTP_SERVER}]:${SMTP_PORT} ${SMTP_USERNAME}:${SMTP_PASSWORD}" >> /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd
  fi
fi

# Set header tag
if [ ! -z "${SMTP_HEADER_TAG}" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_tag"
  echo -e "/^MIME-Version:/i PREPEND RelayTag: $SMTP_HEADER_TAG\n/^Content-Transfer-Encoding:/i PREPEND RelayTag: $SMTP_HEADER_TAG" > /etc/postfix/header_tag
  echo "Setting configuration option SMTP_HEADER_TAG with value: ${SMTP_HEADER_TAG}"
fi

if [ -n "${ADMIN_EMAIL}" ]; then
  echo "Setting root email redirection to ${ADMIN_EMAIL}"
  sed -i -e "s/^#root:.*/root: ${ADMIN_EMAIL}/" /etc/postfix/aliases
fi

# mailman specific options
add_config_value "alias_maps" '$alias_database, cdb:/etc/mailman/aliases'
add_config_value "virtual_alias_maps" 'cdb:/etc/mailman/virtual-mailman'
[ -n "${MAILMAN_DOMAINS}" ] && add_config_value "relay_domains" "$(format_domains postfix "${MAILMAN_DOMAINS}")"

echo 'Configuring mailman:'
MAILMAN_LANG="${MAILMAN_LANG:-ru}"; echo "MAILMAN_LANG=${MAILMAN_LANG}"
MAILMAN_URL_HOST="${MAILMAN_URL_HOST:-$SERVER_HOSTNAME}"; echo "MAILMAN_URL_HOST=${MAILMAN_URL_HOST}"
MAILMAN_EMAIL_HOST="${MAILMAN_EMAIL_HOST:-$MAILMAN_URL_HOST}"; echo "MAILMAN_EMAIL_HOST=${MAILMAN_EMAIL_HOST}"
MAILMAN_URL_PATTERN="${MAILMAN_URL_PATTERN:-https:\/\/%s\/mailman\/}"; echo "MAILMAN_URL_PATTERN=${MAILMAN_URL_PATTERN}"

# sane defaults
[ -n "${MAILMAN_DOMAINS}" ] || MAILMAN_DOMAINS="${MAILMAN_URL_HOST}"
MAILMAN_DOMAINS="$(format_domains mailman "${MAILMAN_DOMAINS}")"

for var in MAILMAN_LANG \
           MAILMAN_URL_HOST \
           MAILMAN_EMAIL_HOST \
           MAILMAN_URL_PATTERN; do
  eval sed -ri -e "s/@${var}@/\$${var}/" /etc/mailman/mm_config.py
done
printf '%s\n' "$MAILMAN_DOMAINS" >> /etc/mailman/mm_config.py

postmap /etc/mailman/virtual-mailman

#Check for subnet restrictions
nets='127.0.0.1/32'
if [ ! -z "${SMTP_NETWORKS}" ]; then
        for i in $(sed 's/,/\ /g' <<<$SMTP_NETWORKS); do
                if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
                        nets+=", $i"
                else
                        echo "$i is not in proper IPv4 subnet format. Ignoring."
                fi
        done
fi
add_config_value "mynetworks" "${nets}"

#Start services
supervisord
