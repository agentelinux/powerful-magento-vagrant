#!/usr/bin/env bash

SAMPLE_DATA=$1
MAGE_VERSION="1.9.1.1"
DATA_VERSION="1.9.1.0"
IP_OR_HOSTNAME="127.0.0.1:8081"
ADMIN_MAIL="krishna@agentelinux.com.br"


SO=$(cat <<EOF

fs.file-max = 2097152
fs.inotify.max_user_watches = 500000
kernel.core_uses_pid = 1
kernel.msgmax = 65536
kernel.msgmnb = 65536
kernel.shmall = 4294967296
kernel.shmmax = 68719476736
kernel.sysrq = 0
net.core.netdev_max_backlog = 262144
net.core.optmem_max = 25165824
net.core.rmem_default = 31457280
net.core.rmem_max = 16777216
net.core.somaxconn = 65535
net.core.wmem_default = 8388608
net.core.wmem_max = 16777216
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.rp_filter = 1
net.ipv4.ip_forward = 0
net.ipv4.ip_local_port_range = 2000 65535
net.ipv4.route.flush = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_mem = 8388608 8388608 8388608
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_rmem = 8192 87380 16777216
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_wmem = 8192 65536 16777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
vm.dirty_background_ratio = 2
vm.dirty_ratio = 60
vm.swappiness = 50
vm.overcommit_memory=1

EOF
)


echo "$SO" > /etc/sysctl.conf

sysctl -q -p

# Pre-Install HHVM
apt-get install -y software-properties-common
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0x5a16e7281be7a449
add-apt-repository 'deb http://dl.hhvm.com/ubuntu trusty main'
apt-key adv --keyserver keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A
add-apt-repository 'deb http://repo.percona.com/apt trusty main'

# Remove extra packages
apt-get autoremove -y apache2


# Update Apt
# --------------------
apt-get update

# Install HHVM
apt-get install -y hhvm
update-rc.d hhvm defaults

#Redis Cache and Session
apt-get install -y redis-server

# Install Apache & PHP
# --------------------
apt-get install -y varnish
apt-get install -y nginx
#apt-get install -y php5-fpm
#apt-get install -y php5-mysqlnd php5-curl php5-xdebug php5-gd php5-intl php-pear php5-imap php5-mcrypt php5-ming php5-ps php5-pspell php5-recode php5-snmp php5-sqlite php5-tidy php5-xmlrpc php5-xsl php-soap
apt-get install -y git-core

# Use HHVM for /usr/bin/php even if you have php-cli installed:
/usr/bin/update-alternatives --install /usr/bin/php5 php5 /usr/bin/hhvm 60

#php5enmod mcrypt

# Delete default apache web dir and symlink mounted vagrant dir from host machine
# --------------------
#mkdir /vagrant/httpdocs
#ln -fs /vagrant/httpdocs /usr/share/nginx/html/public
mkdir /usr/share/nginx/html/public


# Replace contents of default Apache vhost
# --------------------
VHOST=$(cat <<EOF
##
# Vagrant nginx server configuration
##

server {
        listen   8080; ## listen for ipv4; this line is default and implied
        #listen   [::]:80 default ipv6only=on; ## listen for ipv6

        root /usr/share/nginx/html/public;
        index index.php index.html index.htm;

        # Make site accessible from http://localhost/
        server_name localhost;

        ## Main Magento @location

        ## These locations are protected
        location ~ /(app|includes|pkginfo|var|errors/local.xml)/ {
            deny all;
        }

        ## Images
        location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
            expires max;
            log_not_found off;
            access_log off;
            add_header ETag "";
        }

        location =/js/index.php/x.js {
            rewrite ^(.*\.php)/ \$1 last;
        }


        location / {

            try_files \$uri \$uri/ @rewrite;

        }

        location @rewrite {

            rewrite / /index.php?\$args;

        }

        location /doc/ {
                alias /usr/share/doc/;
                autoindex on;
                allow 127.0.0.1;
                deny all;
        }

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000

        location ~ \.php$ {
              expires off;
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              # With HHVM:
              fastcgi_pass 127.0.0.1:9000;
              fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
              fastcgi_index index.php;
              include fastcgi_params;
        }

}
EOF
)

rm -f /etc/nginx/sites-enabled/default
echo "$VHOST" > /etc/nginx/sites-enabled/000-default.conf

wget -qO /etc/nginx/fastcgi_params https://raw.githubusercontent.com/magenx/nginx-config/master/magento/fastcgi_params
wget -qO /etc/nginx/nginx.conf https://raw.githubusercontent.com/magenx/nginx-config/master/magento/nginx.conf
wget -qO /etc/nginx/conf.d/headers.conf https://raw.githubusercontent.com/magenx/nginx-config/master/magento/conf.d/headers.conf


sed -i "s/user  nginx/user www-data/g" /etc/nginx/nginx.conf
sed -i "68d" /etc/nginx/nginx.conf
sed -i "68i     include /etc/nginx/conf.d/*.conf;" /etc/nginx/nginx.conf
sed -i "69i     include /etc/nginx/sites-enabled/*;" /etc/nginx/nginx.conf

service nginx restart

# SET HHVM
/usr/share/hhvm/install_fastcgi.sh
service hhvm restart

# Mysql
# --------------------
# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive
# Install MySQL quietly
#apt-get -q -y install mysql-server-5.5
apt-get -y install percona-server-server-5.6 percona-server-client-5.6

mysql -u root -e "CREATE DATABASE IF NOT EXISTS magentodb"
mysql -u root -e "GRANT ALL PRIVILEGES ON magentodb.* TO 'magentouser'@'localhost' IDENTIFIED BY 'password'"
mysql -u root -e "FLUSH PRIVILEGES"


# Magento
# --------------------
# http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/installing_magento_via_shell_ssh

# Download and extract
if [[ ! -f "/usr/share/nginx/html/public/index.php" ]]; then
  cd /usr/share/nginx/html/public
  git clone https://github.com/OpenMage/magento-mirror .
  chmod -R o+w media var
  chmod o+w app/etc
fi


# Sample Data
if [[ $SAMPLE_DATA == "true" ]]; then
  cd /vagrant

  if [[ ! -f "/vagrant/magento-sample-data-${DATA_VERSION}.tar.gz" ]]; then
    # Only download sample data if we need to
    wget http://www.magentocommerce.com/downloads/assets/${DATA_VERSION}/magento-sample-data-${DATA_VERSION}.tar.gz
  fi

  tar -zxvf magento-sample-data-${DATA_VERSION}.tar.gz
  cp -R magento-sample-data-${DATA_VERSION}/media/* /usr/share/nginx/html/public/media/
  cp -R magento-sample-data-${DATA_VERSION}/skin/*  /usr/share/nginx/html/public/skin/
  mysql -u root magentodb < magento-sample-data-${DATA_VERSION}/magento_sample_data_for_${DATA_VERSION}.sql
  rm -rf magento-sample-data-${DATA_VERSION}
fi


# Run installer
if [ ! -f "/vagrant/httpdocs/app/etc/local.xml" ]; then
  cd /usr/share/nginx/html/public
  sudo /usr/bin/php -f install.php -- --license_agreement_accepted yes \
  --locale en_US --timezone "America/Sao_Paulo" --default_currency USD \
  --db_host localhost --db_name magentodb --db_user magentouser --db_pass password \
  --url "http://${IP_OR_HOSTNAME}/" --use_rewrites yes \
  --use_secure no --secure_base_url "http://${IP_OR_HOSTNAME}/" --use_secure_admin no \
  --skip_url_validation yes \
  --admin_lastname Owner --admin_firstname Store --admin_email "${ADMIN_MAIL}" \
  --admin_username admin --admin_password password123123
  /usr/bin/php -f shell/indexer.php reindexall
fi

# Install n98-magerun
# --------------------
cd /usr/share/nginx/html/public
wget https://raw.github.com/netz98/n98-magerun/master/n98-magerun.phar
chmod +x ./n98-magerun.phar
sudo mv ./n98-magerun.phar /usr/local/bin/


echo -e '\nDAEMON_OPTS="-a :80 \
             -T localhost:6082 \
             -f /etc/varnish/default.vcl \
             -u varnish -g varnish \
             -p thread_pool_min=200 \
             -p thread_pool_max=4000 \
             -p thread_pool_add_delay=2 \
             -p cli_timeout=25 \
             -p cli_buffer=26384 \
             -p esi_syntax=0x2 \
             -p session_linger=100 \
             -S /etc/varnish/secret \
             -s malloc,2G"' >> /etc/default/varnish

service varnish restart

# Configure REDIS Session
sed -i "s/false/true/g" /usr/share/nginx/html/public/app/etc/modules/Cm_RedisSession.xml

sed -i "55d" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "55i <session_save>db</session_save>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "56i <redis_session>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "57i <host>127.0.0.1</host>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "58i <port>6379</port>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "59i <password></password>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "60i <timeout>2.5</timeout>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "61i <persistent></persistent>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "62i <db>0</db>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "63i <compression_threshold>2048</compression_threshold>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "64i <compression_lib>gzip</compression_lib>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "65i <log_level>1</log_level>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "66i <max_concurrency>6</max_concurrency>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "67i <break_after_frontend>5</break_after_frontend>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "68i <break_after_adminhtml>30</break_after_adminhtml>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "69i <first_lifetime>600</first_lifetime>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "70i <bot_first_lifetime>60</bot_first_lifetime>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "71i <bot_lifetime>7200</bot_lifetime>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "72i <disable_locking>0</disable_locking>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "73i <min_lifetime>60</min_lifetime>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "74i <max_lifetime>2592000</max_lifetime>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "75i </redis_session>" /usr/share/nginx/html/public/app/etc/local.xml


# This is a child node of config/global
sed -i "76i <cache>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "77i   <backend>Cm_Cache_Backend_Redis</backend>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "78i   <backend_options>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "79i     <server>127.0.0.1</server>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "80i     <port>6379</port>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "81i     <persistent></persistent> " /usr/share/nginx/html/public/app/etc/local.xml
sed -i "82i     <database>0</database> " /usr/share/nginx/html/public/app/etc/local.xml
sed -i "83i     <password></password>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "84i     <force_standalone>0</force_standalone>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "85i     <connect_retries>1</connect_retries>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "86i     <read_timeout>10</read_timeout> " /usr/share/nginx/html/public/app/etc/local.xml
sed -i "87i     <automatic_cleaning_factor>0</automatic_cleaning_factor>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "88i     <compress_data>1</compress_data>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "89i     <compress_tags>1</compress_tags>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "90i     <compress_threshold>20480</compress_threshold> " /usr/share/nginx/html/public/app/etc/local.xml
sed -i "91i     <compression_lib>gzip</compression_lib>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "92i     <use_lua>0</use_lua>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "93i   </backend_options>" /usr/share/nginx/html/public/app/etc/local.xml
sed -i "94i </cache>" /usr/share/nginx/html/public/app/etc/local.xml

chown -R www-data: /usr/share/nginx/html/public

echo "THE END"
