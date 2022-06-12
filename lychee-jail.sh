#!/bin/sh

# Install Lychee photo manager (https://github.com/LycheeOrg/Lychee)
# in a FreeNAS/TrueNAS jail

# https://forum.freenas-community.org/t/scripted-installation-of-lychee-photo-manager/102

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_NAME="lychee"
JAIL_IP=""
DEFAULT_GW_IP=""
POOL_PATH=""
CONFIG_NAME="lychee-config"

# Check for lychee-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)


# Error checking and config sanity check
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
mountpoint=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "caddy", 
  "ffmpeg",
  "git", 
  "go",
  "mariadb103-server",
  "nano", 
  "p5-Image-ExifTool",
  "php81-bcmath", 
  "php81-ctype", 
  "php81-dom",
  "php81-exif", 
  "php81-extensions", 
  "php81-fileinfo", 
  "php81-gd", 
  "php81-mbstring", 
  "php81-mysqli", 
  "php81-pdo_mysql", 
  "php81-pdo", 
  "php81-pecl-imagick",
  "php81-pecl-redis", 
  "php81-simplexml", 
  "php81-tokenizer", 
  "php81-xml", 
  "php81-zip", 
  "php81-zlib",
  "php81", 
  "redis"
  ]
}
__EOF__

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" \
  ip4_addr="vnet0|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" \
  host_hostname="${JAIL_NAME}" vnet="on"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

# Enable services
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_config=/usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sysrc redis_enable=YES
iocage exec "${JAIL_NAME}" sysrc mysql_enable=YES

# Directory creation and mounting
iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
mkdir -p "${POOL_PATH}"/apps/lychee
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/apps/lychee /usr/local/www nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0
iocage exec "${JAIL_NAME}" cp /mnt/includes/php.ini /usr/local/etc/

# Start and secure database, create Lychee database
iocage exec "${JAIL_NAME}" service mysql-server start
iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE lychee;"
iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON lychee.* TO lychee_user@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf

# Save passwords for later reference
iocage exec "${JAIL_NAME}" echo "MariaDB root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "Lychee database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt

# Create Caddyfile
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/www/Caddyfile
:80 {
	encode gzip

	log {
		output file /var/log/lychee_access.log
		format single_field common_log
	}

	root * /usr/local/www/Lychee/public
	file_server

	php_fastcgi 127.0.0.1:9000

}
__EOF__

# Download and install Composer
iocage exec "${JAIL_NAME}" php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
iocage exec "${JAIL_NAME}" php -r "if (hash_file('sha384', '/tmp/composer-setup.php') === '55ce33d7678c5a611085589f1f3ddf8b3c52d662cd01d4ba75c0ee0459970c2200a51f492d557530c71c15d8dba01eae') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('/tmp/composer-setup.php'); } echo PHP_EOL;"
iocage exec "${JAIL_NAME}" php /tmp/composer-setup.php --install-dir /usr/local/bin --filename composer


# Download and install lychee
iocage exec "${JAIL_NAME}" git clone https://github.com/LycheeOrg/Lychee /usr/local/www/Lychee
iocage exec "${JAIL_NAME}" cp /usr/local/www/Lychee/.env.example /usr/local/www/Lychee/.env
iocage exec "${JAIL_NAME}" sh -c 'cd /usr/local/www/Lychee/ && env COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --prefer-dist'
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/Lychee/
iocage exec "${JAIL_NAME}" sed -i '' "s|DB_CONNECTION=sqlite|DB_CONNECTION=mysql|" /usr/local/www/Lychee/.env
iocage exec "${JAIL_NAME}" sed -i '' "s|DB_HOST=|DB_HOST=localhost|" /usr/local/www/Lychee/.env
iocage exec "${JAIL_NAME}" sed -i '' "s|#DB_DATABASE=|DB_DATABASE=lychee|" /usr/local/www/Lychee/.env
iocage exec "${JAIL_NAME}" sed -i '' "s|DB_USERNAME=|DB_USERNAME=lychee_user|" /usr/local/www/Lychee/.env
iocage exec "${JAIL_NAME}" sed -i '' "s|DB_PASSWORD=|DB_PASSWORD=${DB_PASSWORD}|" /usr/local/www/Lychee/.env
# iocage exec "${JAIL_NAME}" sh -c 'cd /usr/local/www/Lychee/ && php artisan key:generate'

# Includes no longer needed, so unmount
iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

# Start services
iocage exec "${JAIL_NAME}" service redis start
iocage exec "${JAIL_NAME}" service php-fpm start
iocage exec "${JAIL_NAME}" service caddy start

# Finished!
echo "Installation complete!"
echo "Using your web browser, go to http://${JAIL_IP} to log in"
echo "Database passwords are saved in /root/${JAIL_NAME}_db_password.txt"