#!/bin/bash

# Non interactive script that prepares a server with
# Icinga&IcingaWeb. It should work idempotently.
# Warning: running the script again deletes databases.

# Requirements (in /vagrant dir):
# - secrets file (like in secrets_example)
# - archive with configs: icingaweb2_config.tgz
# - script to put secrets in configs: config_parser_v3.sh

# What requires maintenance:
# - addresses of extra repos (Icinga, SCL)
# - PHP
# - icinga master/client monitoring configuration 

# Actions performed:
# - updating the packages,
# - disabling SElinux,
# - install bash completions & reload profile file,
# - install, start & enable firewalld,
# - install EPEL, SCL and Icinga repos,
# - install packages required for IcingaWeb (mostly php),
# - install and secure MariaDB (MySQL)
# - install and configure Icinga (IDO-mysql, api, db),
# - install and configure IcingaWeb (admin user, api, db),
# - set up the host as an icinga master server,
# - move host's icinga config to a correct zone directory.


# TO DO:
# - Make the server work with SELinux.
# - Configure server to use https.
# - Backup databases before destroying them.
# - Move some magic constants into variables defined in the beginning
#   of the script.


###### FUNCTIONS
## Exit on fail.
die(){
  echo "Error in: ${*}." >&2
  echo "Exiting $0." >&2
  exit 1
}

###### Preparing the server and environment.
## Check if running as root.
if [[ $(id -u) != 0 ]]; then
  die "This script is supposed to be run as root or with sudo."
fi

## Check if /vagrant dir contains required files.
# - secrets file
if [[ ! -e /vagrant/secrets ]]; then
  die 'File /vagrant/secrets not found.'
fi
# - script seeding secrets into icinga config.
if [[ ! -e /vagrant/config_parser_v3.sh ]]; then
  die 'File /vagrant/config_parser_v3.sh not found.'
fi
# - archive with icinga configs.
if [[ ! -e /vagrant/icingaweb2_config.tgz ]]; then
  die 'File /vagrant/icingaweb2_config.tgz not found.'
fi


## Read in Variables
source /vagrant/secrets
# TODO: Move constant into a variable.

## Update all packages.
yum update -y || die 'Failed to `yum update`.'

### Disable SElinux
#sed -i 's/SELINUX=.*/SELINUX=permissive/' /etc/selinux/config \
#    || die "Failed to set SElinux to permissive in /etc/selinux/config."
#setenforce permissive || die "Failed to set SElinux to permissive."

## Installing bash completions.
yum install bash-completion bash-completion-extras -y \
    || die "Failed to install bash-completions."
source /etc/profile || die "Failed to source /etc/profile."

## Install firewalld.
yum install firewalld -y || die "Failed to install firewalld."
systemctl enable --now firewalld || die "Failed to activate firewalld."



###### Prepare for Icinga2 installation.
## Enable installation of docs by yum (often disabled on cloud 
# instances).
sed -i '/tsflags/s/^/#/' /etc/yum.conf \
|| die "sed -i '/tsflags/s/^/#/' /etc/yum.conf"
# Required for icingaweb database schema which is a doc.

## Setting up package repositories:
# Check if Icinga repo is already installed.
if ! yum repolist | grep ^icinga-stable-release ; then
  # Icinga files.
  yum install -y https://packages.icinga.com/epel/icinga-rpm-release-7-latest.noarch.rpm \
    || die "yum install -y https://packages.icinga.com/epel/icinga-rpm-release-7-latest.noarch.rpm"
fi
# EPEL.
yum install -y epel-release|| die "yum install -y epel-release"
# SCL for newer PHP.
yum install -y centos-release-scl|| die "yum install -y centos-release-scl"

###### Installation of the MySQL Database (MariaDB)
## Install mariadb.
yum remove -y mariadb-server \
|| die "yum remove -y mariadb-server"

rm -rf /var/lib/mysql/ \
|| die "rm -rf /var/lib/mysql/"

yum install -y mariadb-server \
|| die "yum install -y mariadb-server"

systemctl enable --now mariadb \
|| die "systemctl enable --now mariadb"

## Secure mariadb.
# Check if we can access the db.
mysql -uroot <<<"" \
|| die "mysql -uroot <<<"""

# Check if db root password is defined.
[[ -z $DB_root_pass ]] \
  && die "$DB_root_pass not defined."

# Set the root password.
# Delete anonymous users.
# Restrict root login to localhost.
# Remove the test database.
# Re-read access db (to block paswordless db root login until restart).
if ! mysql -uroot <<EOF
UPDATE mysql.user SET Password=PASSWORD('$DB_root_pass') WHERE User='root';                                                          
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');                                         
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
then die "mysql -uroot <<EOF"
fi



###### Installation of Icinga.
## How to check if configuration is correct.
#icinga2 daemon -C

## Install services and Icinga components.
#(installing all at once because of unusual location of scl-php-73)
yum install -y \
    icinga2 \
    nagios-plugins-all \
    icinga2-ido-mysql \
    icingaweb2 \
    icingacli \
    sclo-php73-php-pecl-imagick \
    httpd \
      || die 'yum install icinga components'


## Enable httpd and Icinga.
systemctl enable --now icinga2 \
  || die 'systemctl enable --now icinga2'
systemctl enable --now httpd \
  || die 'systemctl enable --now httpd'

## Configure PHP
# Set timezone to UTC.
sed -i '/;date.timezone =/a date.timezone = "UTC"' /etc/opt/rh/rh-php73/php.ini \
  || die 'sed -i '\''/;date.timezone =/a date.timezone = "UTC"'\'' /etc/opt/rh/rh-php73/php.ini'


## Configure the database for Icinga.
# Check if icinga2dbpass is defined.
[[ -z $icinga2dbpass ]] \
  && die '$icinga2dbpass not defined.'

# Create the database and it's user.
if ! mysql -uroot -p"${DB_root_pass}" <<EOF
CREATE DATABASE icinga;
GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE VIEW, INDEX, EXECUTE ON icinga.* TO 'icinga'@'localhost' IDENTIFIED BY '${icinga2dbpass}';
EOF
then
  die "Create IcingaDB/Icinga DB User."
fi
# Import DB schema.
mysql -uroot -p"${DB_root_pass}" icinga < \
      /usr/share/icinga2-ido-mysql/schema/mysql.sql \
      || die 'Initialize icinga database.'

# Tell Icinga how to connect to the database.
sed -i -e '\#//user =#s#//user#user#' \
    -e "\#//password =#s#icinga#${icinga2dbpass}#" \
    -e '\#//password =#s#//password#password#' \
    -e '\#//host =#s#//host#host#' \
    -e '\#//database =#s#//database#database#' \
    /etc/icinga2/features-available/ido-mysql.conf \
    || die 'Set up ido-mysql with credentials.'



# Enable the ido-mysql feature in Icinga.
icinga2 feature enable ido-mysql \
	|| die 'icinga2 feature enable ido-mysql'
systemctl restart icinga2.service \
	  || die 'systemctl restart icinga2'
systemctl restart mariadb.service \
	  || die 'systemctl restart mariadb.service'


###### Installing IcingaWeb2
# Start and enable php-fpm service.
systemctl enable --now rh-php73-php-fpm.service  \
	  || die "systemctl enable --now rh-php73-php-fpm.service "

### Icinga Web 2 Manual Database Setup
# Check if icingaweb2dbpass is defined.
[[ -z $icingaweb2dbpass ]] \
  && die '$icingaweb2dbpass not defined.'

# Create the database and load the database schema.
if ! mysql -uroot -p"${DB_root_pass}" <<EOF 
CREATE DATABASE icingaweb2;
GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE VIEW, CREATE TEMPORARY TABLES, INDEX, EXECUTE ON icingaweb2.* TO 'icingaweb2'@'localhost' IDENTIFIED BY '${icingaweb2dbpass}';
EOF
then
  die "Failed to create database user for icingaweb."
fi
mysql -uroot -p"${DB_root_pass}" icingaweb2 < /usr/share/doc/icingaweb2/schema/mysql.schema.sql \
|| die 'mysql -uroot -p"${DB_root_pass}" icingaweb2 < /usr/share/doc/icingaweb2/schema/mysql.schema.sql'

# Add a group for administrators.
if ! mysql -uroot -p"${DB_root_pass}" icingaweb2 <<EOF 
INSERT INTO icingaweb_group VALUES (1,'Administrators',NULL,'$(date +%F' '%T)',NULL);
EOF
then die 'Adding icingaweb2 admin user group.'
fi

## Generate password hash for the icingaweb admin user.
# Find php binary (scl packages are by default installed in non default paths).
php_binary_path="$(find / -type f -name 'php' | grep '/usr/bin/php$')" \
  || die 'php_binary_path="$(find / -type f -name "php" | grep "/usr/bin/php$")"'
# There can be only one php binary.
if [[ $(echo "${php_binary_path}" | wc -w) -ne 1 ]]; then
  die 'Too many php versions.'
fi
# Check if icingaweb admin password exists.
[[ -z $icingaweb2adminpass ]] && die 'icingaweb2adminpass not defined'
# Hash the password
password_hash=$(${php_binary_path} -r \
   "echo password_hash(\"${icingaweb2adminpass}\", PASSWORD_DEFAULT);")
[[ -z $password_hash ]] && die 'password_hash not defined'

## Add a new admin user for icingaweb.
# Check if icingaweb admin username exists.
[[ -z $icingaweb2adminuser ]] && die 'icingaweb2adminuser not defined'

# Send query to the db.
user_creation_date=$(date +%F' '%T)
if ! mysql -uroot -p"${DB_root_pass}" icingaweb2 <<EOF
INSERT INTO icingaweb_group_membership VALUES (1,'${icingaweb2adminuser}','${user_creation_date}',NULL);
INSERT INTO icingaweb_user VALUES ('${icingaweb2adminuser}',1,'${password_hash}','${user_creation_date}',NULL);
EOF
then die 'SQL query to add admin user(s) to the icingaweb2 database.'
fi

### Icinga Web 2 manual configuration files setup.



# Set up firewall.
firewall-cmd --permanent --add-service=http \
	     || die 'firewall-cmd --permanent --add-service=http'
firewall-cmd --reload \
	     || die 'firewall-cmd --reload'

## Set up Icinga 2 REST API. (also enables the icinga api feature)
# Run icinga auto-setup.
icinga2 api setup > /dev/null \
	|| die 'icinga2 api setup'
# Check if icingaweb2apipass is defined.
[[ -z $icingaweb2apipass ]] \
  && die '$icingaweb2apipass not defined.'

# Remove old icingaweb2 entry if it exists.
sed -i '/object ApiUser "icingaweb2"/,/^[ ]*}$/d' /etc/icinga2/conf.d/api-users.conf \
  || die 'sed -i /etc/icinga2/conf.d/api-users.conf'

# Add a new icingaweb2api entry.
if ! cat >> /etc/icinga2/conf.d/api-users.conf <<EOF
object ApiUser "icingaweb2" {
  password = "${icingaweb2apipass}"
  permissions = [ "status/query", "actions/*", "objects/modify/*", "objects/query/*" ]
}
EOF
then
  die 'Adding icingaweb2api user.'
fi

# Restart Icinga 2 to activate the configuration.
systemctl restart icinga2.service \
	  || die 'systemctl restart icinga2.service'

### Install config files
# Prepare dir for the config files
icingacli module enable setup \
  || die 'icingacli module enable setup'

icingacli setup config directory --group icingaweb2 \
  || die 'icingacli setup config directory --group icingaweb2'

# Check archive hash.
# correct_config_hash is in secrets
actual_config_hash="$(sha256sum /vagrant/icingaweb2_config.tgz | awk '{print $1}')"
[[ "${correct_config_hash}" != "${actual_config_hash}" ]] \
  && {
  echo "Expected hash: ${correct_config_hash}." >&2
  echo "Actual hash: ${actual_config_hash}." >&2
  die 'Comparing config hashes.'
}
# Extract archive
sudo tar -xvzf /vagrant/icingaweb2_config.tgz -C /etc/  \
     > /dev/null \
  || die 'sudo tar -xvzf /vagrant/icingaweb2_config.tgz -C /etc/'
# Create a tempfile to hold command output.
output_holder=$(mktemp) || die "Failed to create a tempfile."
trap 'rm -f ${output_holder}; exit' EXIT
# Replace placeholder values with secrets.
/vagrant/config_parser_v3.sh > "${output_holder}" \
  || die 'Running config_parser_v3.sh.'
# Verify that secrets are where they should.
diff - "${output_holder}" <<EOF
Replaced icingaweb2dbpass in /etc/icingaweb2/resources.ini.
Replaced icinga2dbpass in /etc/icingaweb2/resources.ini.
Replaced icingaweb2adminuser in /etc/icingaweb2/roles.ini.
Replaced icingaweb2apipass in /etc/icingaweb2/modules/monitoring/commandtransports.ini.
EOF
[[ ! $? ]]\
  && die 'config_parser_v3.sh output is not what was expected'
# Set correct ownerships for config files.
while read -r line; do
  config_loc="${line%%:*}"
  config_ownership="${line#*:}"
  chown "${config_ownership}" "/etc/${config_loc}"       \
    || die "chown "${config_ownership}" "/etc/${config_loc}""
done < /etc/permissionsforconfig
rm /etc/permissionsforconfig \
  || die 'rm /etc/permissionsforconfig'

# Configure server as a master icinga node.
icinga2 node setup --master \
  || die 'icinga2 node setup --master'
systemctl restart icinga2.service \
  || die 'systemctl restart icinga2.service'

# Create the Master Zone configuration directory and move
# there the example host configuration.
if [[ ! -d '/etc/icinga2/zones.d/master' ]]; then
  # Only create the directory if it doesn't exist.
  mkdir /etc/icinga2/zones.d/master \
    || die 'mkdir /etc/icinga2/zones.d/master'
fi
master_hostname="$(hostname)"
if [ -z "$master_hostname" ]; then
  die 'Empty hostname.'
fi
master_configuration=\
"/etc/icinga2/zones.d/master/${master_hostname}.conf"
# Check if the configuration exists already.
if [ ! -s "$master_configuration" ]; then
  # Move the configuration.
  mv /etc/icinga2/conf.d/hosts.conf "$master_configuration"\
     || die 'Moving icinga2 hosts.conf into zone dir.'
  # Change from default vhost check into premade IcingaWeb check.
  sed '\#\s\+vars.http_vhosts#,+2s#^\s\+#&//#p' \
      "$master_configuration" > "$output_holder" \
      || die 'Commenting old vhost check.'
  sed '/http_vhosts\["Icinga Web 2"\]/,+2s#^\(\s\+\)//#\1#' \
      "$output_holder" > "$master_configuration" \
      || die 'Uncommenting IcingaWeb2 vhost check.'
else
  echo "Warning:"
  echo "/etc/icinga2/zones.d/master/${master_hostname}.conf exists."
  echo "Not changing the vhosts check."
fi
systemctl restart icinga2.service \
  || die 'systemctl restart icinga2.service'

echo "Script finished succefully."
exit 0
