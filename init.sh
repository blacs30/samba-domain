#!/bin/bash
if [ ! -z "$DEBUG" ]; then
    set -x
fi
if [ ! -z "$FAILONERROR" ]; then
    set -e
fi

cp -f /etc/freeradius/mods-available/detail.log.tpl /etc/freeradius/mods-available/detail.log

# reload samba daily to reduce memory usage
if [[ "$SET_CRON" != "OFF" ]]; then
  echo '#!/bin/sh' > /etc/cron.daily/restartsamba
  echo 'supervisorctl reload samba' >> /etc/cron.daily/restartsamba
  chmod +x /etc/cron.daily/restartsamba
  service cron start
fi


appSetup () {

  # Set variables
  DOMAIN=${DOMAIN:-SAMDOM.LOCAL}
  DOMAINPASS=${DOMAINPASS:-youshouldsetapassword}
  JOIN=${JOIN:-false}
  JOINSITE=${JOINSITE:-NONE}
  if [ ! -z "${JOINSERVER}" ]; then JOINSERVER="--server=${JOINSERVER}"; fi
  MULTISITE=${MULTISITE:-false}
  NOCOMPLEXITY=${NOCOMPLEXITY:-false}
  INSECURELDAP=${INSECURELDAP:-false}
  DNSFORWARDER=${DNSFORWARDER:-NONE}
  HOSTIP=${HOSTIP:-NONE}
  EDIT_SAMBA_CONF=${EDIT_SAMBA_CONF:-false}

  LDOMAIN=${DOMAIN,,}
  UDOMAIN=${DOMAIN^^}
  URDOMAIN=${UDOMAIN%%.*}

  FREERADIUS=${FREERADIUS:-NONE}

  # If multi-site, we need to connect to the VPN before joining the domain
  if [[ ${MULTISITE,,} == "true" ]]; then
    /usr/sbin/openvpn --config /docker.ovpn &
    VPNPID=$!
    echo "Sleeping 30s to ensure VPN connects ($VPNPID)";
    sleep 30
  fi

        # Set host ip option
        if [[ "$HOSTIP" != "NONE" ]]; then
    HOSTIP_OPTION="--host-ip=$HOSTIP"
        else
    HOSTIP_OPTION=""
        fi

  # Set up samba
  mv /etc/krb5.conf /etc/krb5.conf.orig
  echo "[libdefaults]" > /etc/krb5.conf
  echo "    dns_lookup_realm = false" >> /etc/krb5.conf
  echo "    dns_lookup_kdc = true" >> /etc/krb5.conf
  echo "    default_realm = ${UDOMAIN}" >> /etc/krb5.conf


  # If the finished file isn't there, this is brand new, we're not just moving to a new container
  if [[ ! -f /etc/samba/external/smb.conf ]]; then
      test -f /etc/samba/smb.conf && [ -w /etc/samba/smb.conf ] && mv -f /etc/samba/smb.conf /etc/samba/smb.conf.orig
    if [[ ${JOIN,,} == "true" ]]; then
      if [[ ${JOIN_WITH_KERBEROS,,} == "true" ]]; then
        echo ${DOMAINPASS} | kinit Administrator
        if [[ ${JOINSITE} == "NONE" ]]; then
            samba-tool domain join ${LDOMAIN} DC -k yes --dns-backend=SAMBA_INTERNAL ${JOINSERVER} --option="bind interfaces only=yes" --option="interfaces=lo ${BIND_IF}"
        else
            samba-tool domain join ${LDOMAIN} DC -k yes --dns-backend=SAMBA_INTERNAL --site=${JOINSITE} ${JOINSERVER} --option="bind interfaces only=yes" --option="interfaces=lo ${BIND_IF}"
        fi
      else

        if [[ ${JOINSITE} == "NONE" ]]; then
            samba-tool domain join ${LDOMAIN} DC -U"${URDOMAIN}\administrator" --password=${DOMAINPASS} --dns-backend=SAMBA_INTERNAL ${JOINSERVER} --option="bind interfaces only=yes" --option="interfaces=lo ${BIND_IF}"
        else
            samba-tool domain join ${LDOMAIN} DC -U"${URDOMAIN}\administrator" --password=${DOMAINPASS} --dns-backend=SAMBA_INTERNAL --site=${JOINSITE} ${JOINSERVER} --option="bind interfaces only=yes" --option="interfaces=lo ${BIND_IF}"
        fi
      fi
    else
        samba-tool domain provision --use-rfc2307 --domain=${URDOMAIN} --realm=${UDOMAIN} --server-role=dc --dns-backend=SAMBA_INTERNAL --adminpass=${DOMAINPASS} ${HOSTIP_OPTION}
      if [[ ${NOCOMPLEXITY,,} == "true" ]]; then
        samba-tool domain passwordsettings set --complexity=off
        samba-tool domain passwordsettings set --history-length=0
        samba-tool domain passwordsettings set --min-pwd-age=0
        samba-tool domain passwordsettings set --max-pwd-age=0
      fi
    fi

    if [[ ${EDIT_SAMBA_CONF,,} == "true" ]]; then
      sed -i "/\[global\]/a \
        \\\tidmap_ldb:use rfc2307 = yes\\n\
        wins support = yes\\n\
        template shell = /bin/bash\\n\
        winbind nss info = rfc2307\\n\
        idmap config ${URDOMAIN}: range = 10000-20000\\n\
        idmap config ${URDOMAIN}: backend = ad\
        " /etc/samba/smb.conf
    fi

    if [[ $DNSFORWARDER != "NONE" ]]; then
        sed -i "/\[global\]/a \
          \\\tdns forwarder = ${DNSFORWARDER}\
          " /etc/samba/smb.conf
    fi

    if [[ ${INSECURELDAP,,} == "true" ]]; then
        sed -i "/\[global\]/a \
          \\\tldap server require strong auth = no\
          " /etc/samba/smb.conf
    fi

    # Once we are set up, we'll make a file so that we know to use it if we ever spin this up again
    if [[ ${FREERADIUS,,} == "true" ]]; then
        test -f /provided/smb.conf && cp -v /provided/smb.conf /etc/samba/smb.conf
        test -f /etc/samba/smb.conf && cp -v /etc/samba/smb.conf /etc/samba/external/smb.conf
    else
        test -f /etc/samba/smb.conf && cp -v /etc/samba/smb.conf /etc/samba/external/smb.conf
    fi

  else
      if [[ ${FREERADIUS,,} == "true" ]]; then
          [ -w /etc/samba/smb.conf ] && test -f /provided/smb.conf && cp -v /provided/smb.conf /etc/samba/smb.conf
      else
          [ -w /etc/samba/smb.conf ] && cp -v /etc/samba/external/smb.conf /etc/samba/smb.conf
      fi
  fi

  # Set up supervisor
  echo "[supervisord]" > /etc/supervisor/conf.d/supervisord.conf
  echo "nodaemon=true" >> /etc/supervisor/conf.d/supervisord.conf
  echo "" >> /etc/supervisor/conf.d/supervisord.conf
  echo "[program:samba]" >> /etc/supervisor/conf.d/supervisord.conf
  echo "command=/usr/sbin/samba -i" >> /etc/supervisor/conf.d/supervisord.conf
  if [[ ${MULTISITE,,} == "true" ]]; then
    if [[ -n $VPNPID ]]; then
      kill $VPNPID
    fi
    echo "" >> /etc/supervisor/conf.d/supervisord.conf
    echo "[program:openvpn]" >> /etc/supervisor/conf.d/supervisord.conf
    echo "command=/usr/sbin/openvpn --config /docker.ovpn" >> /etc/supervisor/conf.d/supervisord.conf
  fi
  if [[ ${FREERADIUS,,} == "true" ]]; then
      echo "" >> /etc/supervisor/conf.d/supervisord.conf
      echo "[program:freeradius]" >> /etc/supervisor/conf.d/supervisord.conf
      echo "command=/usr/sbin/freeradius -f" >> /etc/supervisor/conf.d/supervisord.conf
  fi


  appStart
}

appStart () {
  /usr/bin/supervisord
}

function clients_config {
    local CONF=/etc/freeradius/clients.conf
    if [ ! -z $FREERADIUS_CLIENT_HOST ]; then
        cp -f ${CONF}.tpl ${CONF}
        echo $FREERADIUS_CLIENT_HOST
        sed -i "s/FREERADIUS_CLIENT_HOST/$FREERADIUS_CLIENT_HOST/g" ${CONF}
    else
        return 0
    fi

    if [ ! -z $FREERADIUS_CLIENT_SECRET ]; then
        echo $FREERADIUS_CLIENT_SECRET
        sed -i "s/FREERADIUS_CLIENT_SECRET/$FREERADIUS_CLIENT_SECRET/g" ${CONF}
    fi
}

function proxy_config {
    local CONF=/etc/freeradius/proxy.conf
    if [ ! -z $FREERADIUS_PROXY_SECRET ]; then
        cp -f ${CONF}.tpl ${CONF}
        echo $FREERADIUS_PROXY_SECRET
        sed -i "s/FREERADIUS_PROXY_SECRET/$FREERADIUS_PROXY_SECRET/g" ${CONF}
    else
        return 0
    fi

    if [ ! -z $FREERADIUS_ACCOUNT_HOST ]; then
        echo $FREERADIUS_ACCOUNT_HOST
        sed -i "s/FREERADIUS_ACCOUNT_HOST/$FREERADIUS_ACCOUNT_HOST/g" ${CONF}
    fi
}

function eap_config {
    local CONF=/etc/freeradius/mods-available/eap
    if [ ! -z $SSL_PRIV_KEY_PASSWORD ]; then
        cp -f ${CONF}.tpl ${CONF}
        echo $SSL_PRIV_KEY_PASSWORD
        sed -i "s/SSL_PRIV_KEY_PASSWORD/$SSL_PRIV_KEY_PASSWORD/g" ${CONF}
    else
        return 0
    fi
}

if [[ ${FREERADIUS,,} == "true" ]]; then
    usermod -a -G winbindd_priv freerad;
    usermod -a -G root freerad;
    chmod 755 -R /var/run/samba;
    chown root:winbindd_priv /var/lib/samba/winbindd_privileged/;

    clients_config
    proxy_config
    eap_config
fi


case "$1" in
  start)
    if [[ -f /etc/samba/external/smb.conf ]]; then
      [ -w /etc/samba/smb.conf ] && cp -v /etc/samba/external/smb.conf /etc/samba/smb.conf
      appStart
    else
      echo "Config file is missing."
    fi
    ;;
  setup)
    # If the supervisor conf isn't there, we're spinning up a new container
    if [[ -f /etc/supervisor/conf.d/supervisord.conf ]]; then
      appStart
    else
      appSetup
    fi
    ;;
esac

exit 0
