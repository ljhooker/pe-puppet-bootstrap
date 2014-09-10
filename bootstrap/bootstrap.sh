#!/bin/sh
###############################################################################
# Puppet Enterprise Installer Wrapper
#
# This wraps the PE installer to make for a more automated split custom split
# installation.
###############################################################################

PE_VERSION="3.3.2"
INSTALL_PATH="/vagrant/puppet/pe/puppet-enterprise-${PE_VERSION}-el-6-x86_64"
ANSWER_PATH="/vagrant/puppet/answers"

## The domain name to use for the hosts' fqdn
DOMAIN="vagrant.vm"

## The generic name that points to active Puppet Master(s)
PUPPETMASTER="puppetmaster"

## The generic name that points to an active CA
PUPPETCA="puppetca"

## The name that points to the primary CA
PUPPETCA01="puppetca01"

## The name that points to the secondary CA
PUPPETCA02="puppetca02"

## The generic name that points to an active PuppetDB instance
PUPPETDB="puppetdb"

## The name that points to the primary PuppetDB instance
PUPPETDB01="puppetdb01"

## The name that points to the secondary PuppetDB instance
PUPPETDB02="puppetdb02"

## The generic name that points to an active PostgreSQL instance for PuppetDB
PUPPETDBPG="puppetdbpg"

## The generic name that points to an active console
PUPPETCONSOLE="puppetconsole"

## The name that points to the primary console
PUPPETCONSOLE01="puppetconsole01"

## The name that points to the secondary console
PUPPETCONSOLE02="puppetconsole02"

## The generic name that points to an active PostgreSQL instance for the console
PUPPETCONSOLEPG="puppetconsolepg"

################################################################################
## Probably don't need to modify below this
################################################################################

echo
echo "===================================================================="
echo "Select which node to install:"
echo
echo "  [1] ${PUPPETCA01}"
echo "  [2] ${PUPPETDB01}"
echo "  [3] ${PUPPETCONSOLE01}"
echo
echo "  [4] ${PUPPETCA02}"
echo "  [5] ${PUPPETDB02}"
echo "  [6] ${PUPPETCONSOLE02}"
echo
read -p "Selection: " server_role

txtred="\033[0;31m" # Red
txtgrn="\033[0;32m" # Green
txtylw="\033[0;33m" # Yellow
txtblu="\033[0;34m" # Blue
txtpur="\033[0;35m" # Purple
txtcyn="\033[0;36m" # Cyan
txtwht="\033[0;37m" # White
txtrst="\033[0m"

function install_pe() {
  ANSWERS="$1"
  "${INSTALL_PATH}/puppet-enterprise-installer" -A "${ANSWER_PATH}/${ANSWERS}.txt"
}

function has_pe() {
  if [ -f "/opt/puppet/bin/puppet" ]; then
    return 0
  else
    return 1
  fi
}

function apply_puppet_role() {
  echo "==> Applying Puppet role of ${1}"
  /opt/puppet/bin/puppet apply -e "include ${1}" \
    --modulepath=site:modules:/opt/puppet/share/puppet/modules
}

function ca_clean_cert() {
  echo -e "${txtylw}"
  echo "#=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+="
  echo -e "${txtrst}"
  echo "# You now need to clean the certificate for ${1} on the CA"
  echo "    puppet cert clean ${1}"
  echo
  read -p "# Press 'y' when the certificate has been cleaned: " cert_clean
  while [ "${cert_clean}" != "y" ]; do
    ca_clean_cert $1
  done
}

function ca_sign_cert() {
  echo -e "${txtylw}"
  echo "#=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+="
  echo -e "${txtrst}"
  echo "# You now need to sign the certificate for ${1} on the CA"
  echo "    puppet cert sign --allow-dns-alt-names ${1}"
  echo
  read -p "# Press 'y' when the certificate has been signed: " sign_cert
  while [ "${sign_clean}" != "y" ]; do
    ca_sign_cert $1
  done
}

function confirm_install() {
  echo -e "** You have selected to install ${txtylw}${1}${txtrst} **"
  echo
  read -p "Press 'y' to proceed: " proceed_install
  if [ "${proceed_install}" != "y" ]; then
    echo "Exiting."
    exit 0
  fi
}

case $server_role in
  #############################################################################
  ## Primary CA
  #############################################################################
  1|$PUPPETCA01)
    ## Primary CA
    ANSWERS="puppetca01"
    ROLE="role::puppet::ca"
    ALT_NAMES="${PUPPETCA01},${PUPPETCA02}.${DOMAIN},${PUPPETCA02},${PUPPETCA}.${DOMAIN},${PUPPETCA},${PUPPETMASTER}.${DOMAIN},${PUPPETMASTER}"

    confirm_install "${PUPPETCA01}"

    if ! has_pe; then
      install_pe $ANSWERS
    fi

    ## Install some needed software
    /opt/puppet/bin/puppet resource package git ensure=present || \
      (echo "git failed to install; exiting." && exit 1)

    /opt/puppet/bin/gem install r10k || \
      (echo "r10k failed to install; exiting" && exit 1)


    ## Use r10k to fetch all the modules needed
    cd "../"
    /opt/puppet/bin/r10k Puppetfile install -v || \
      (echo "r10k didn't exit cleanly; exiting" && exit 1)

    apply_puppet_role "${ROLE}"
    echo "==> ${PUPPETCA01} complete"
  ;;
  #############################################################################
  ## Secondary CA
  #############################################################################
  4|$PUPPETCA02)
    ## Secondary CA
    ANSWERS="puppetca02"
    ROLE="role::puppet::ca"
    ALT_NAMES="${PUPPETCA01}.${DOMAIN},${PUPPETCA01},${PUPPETCA02},${PUPPETCA}.${DOMAIN},${PUPPETCA},${PUPPETMASTER}.${DOMAIN},${PUPPETMASTER}"

    confirm_install "${PUPPETCA02}"

    if ! has_pe; then
      install_pe $ANSWERS
    fi

    apply_puppet_role "${ROLE}"
    echo "==> ${PUPPETCA02} complete"
    echo "#######################################################################"
    echo "# You will need to copy the /etc/puppetlabs/puppet/ssl directory from"
    echo "# ${PUPPETCA01}.${DOMAIN} to the same location on this node."
    echo "# Ensure that permissions and ownership are preserved"
    echo "#"
    echo "# You should do this after every other node is spun up."
    echo "# After copied, run the following on this node:"
    echo "#    puppet agent -t --server ${PUPPETCA01}.${DOMAIN}"
    echo "#######################################################################"
  ;;
  #############################################################################
  ## Primary and Secondary PuppetDB
  #############################################################################
  2|5|$PUPPETDB01|$PUPPETDB02)
    case $server_role in
      2|$PUPPETDB01)
        ## Primary PuppetDB server
        ANSWERS="puppetdb01"
        NAME="${PUPPETDB01}"
      ;;
      5|$PUPPETDB02)
        ANSWERS="puppetdb02"
        NAME="${PUPPETDB02}"
      ;;
    esac
    ALT_NAMES="${NAME},${PUPPETDB}.${DOMAIN},${PUPPETDB},${PUPPETDBPG}.${DOMAIN},${PUPPETDBPG}"
    ROLE="role::puppet::puppetdb"

    confirm_install "${NAME}"

    if ! has_pe; then
      install_pe $ANSWERS
    fi

    echo "==> Setting certificate alternate names"
    /opt/puppet/bin/augtool set '/files//puppet.conf/main/dns_alt_names' "${ALT_NAMES}"

    echo "==> Removing SSL data"
    rm -rf /etc/puppetlabs/puppet/ssl
    rm -rf /etc/puppetlabs/puppetdb/ssl

    ca_clean_cert "${NAME}.${DOMAIN}"

    echo "==> Running Puppet agent to create CSR"
    /opt/puppet/bin/puppet agent -t

    ca_sign_cert "${NAME}.${DOMAIN}"

    echo "==> Running Puppet agent to retrieve signed certificate"
    echo "    You will see some errors here, but that should be okay."
    /opt/puppet/bin/puppet agent -t

    apply_puppet_role "${ROLE}"

    echo "==> Restarting the pe-puppetdb service"
    service pe-puppetdb restart

    echo "==> ${NAME} complete"
  ;;
  #############################################################################
  ## Primary Console
  #############################################################################
  3|$PUPPETCONSOLE01)
    ANSWERS="puppetconsole01"
    ROLE="role::puppet::console"
    ALT_NAMES="${PUPPETCONSOLE01},${PUPPETCONSOLE}.${DOMAIN},${PUPPETCONSOLE},${PUPPETCONSOLEPG}.${DOMAIN},${PUPPETCONSOLEPG}"

    confirm_install "${PUPPETCONSOLE01}"

    if ! has_pe; then
      install_pe $ANSWERS
    fi

    echo "==> Setting certificate alternate names"
    /opt/puppet/bin/augtool set '/files//puppet.conf/main/dns_alt_names' "${ALT_NAMES}"


    echo "==> Removing SSL data"
    rm -rf /etc/puppetlabs/puppet/ssl
    rm -f /opt/puppet/share/puppet-dashboard/certs/*

    echo "==> Running Puppet agent to create CSR"
    /opt/puppet/bin/puppet agent -t

    ca_sign_cert "${PUPPETCONSOLE01}.${DOMAIN}"

    ca_clean_cert "pe-internal-dashboard"

    echo "==> Running Puppet agent to retrieve signed certificate"
    echo "    You will see some errors here, but that should be okay."
    /opt/puppet/bin/puppet agent -t

    apply_puppet_role "${ROLE}"

  ;;
  #############################################################################
  ## Secondary Console
  #############################################################################
  6|$PUPPETCONSOLE02)
    ANSWERS="puppetconsole02"
    ROLE="role::puppet::console"
    ALT_NAMES="${PUPPETCONSOLE02},${PUPPETCONSOLE}.${DOMAIN},${PUPPETCONSOLE},${PUPPETCONSOLEPG}.${DOMAIN},${PUPPETCONSOLEPG}"

    confirm_install "${PUPPETCONSOLE02}"

    if [ ! -d "/opt/puppet/share/puppet-dashboard/certs" ]; then
      echo "#######################################################################"
      echo "# You must copy the /opt/puppet/share/puppet-dashboard/certs"
      echo "# directory from ${PUPPETCONSOLE01}.${DOMAIN} to the same location on"
      echo "# this node.  Ensure that permissions and ownership are preserved"
      echo "#"
      echo "# Example:"
      echo "#   On this node:"
      echo "     mkdir -p /opt/puppet/share/puppet-dashboard"
      echo "     chown 496: /opt/puppet/share/puppet-dashboard"
      echo
      echo "     rsync -avzp -e 'ssh' \\"
      echo "        ${PUPPETCA01}:/opt/puppet/share/puppet-dashboard/certs/ \\"
      echo "        /opt/puppet/share/puppet-dashboard/certs/"
      echo "#######################################################################"
      exit 1
    fi

    if ! has_pe; then
      install_pe $ANSWERS
    fi

    echo "==> Setting certificate alternate names"
    /opt/puppet/bin/augtool set '/files//puppet.conf/main/dns_alt_names' "${ALT_NAMES}"

    #apply_puppet_role "${ROLE}"

    echo "==> Removing SSL data"
    rm -rf /etc/puppetlabs/puppet/ssl

    echo "==> Running Puppet agent to create CSR"
    /opt/puppet/bin/puppet agent -t

    ca_sign_cert "${PUPPETCONSOLE02}.${DOMAIN}"

    echo "==> ${PUPPETCONSOLE02} complete"
  ;;
  *)
    echo "Unknown selection: ${server_role}"
    exit 1
  ;;
esac

