#!/usr/bin/env bash

SAMPLE_DATA=$1
MAGE_VERSION="1.9.1.1"
DATA_VERSION="1.9.1.0"


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
vm.swappiness = 10


EOF
)


echo "$SO" > /etc/sysctl.conf

sysctl -q -p

# Update Apt
# --------------------
apt-get update

# Install Apache & PHP
# --------------------
apt-get install -y varnish
apt-get install -y nginx
apt-get install -y php5-fpm
apt-get install -y php5-mysqlnd php5-curl php5-xdebug php5-gd php5-intl php-pear php5-imap php5-mcrypt php5-ming php5-ps php5-pspell php5-recode php5-snmp php5-sqlite php5-tidy php5-xmlrpc php5-xsl php-soap

php5enmod mcrypt

# Delete default apache web dir and symlink mounted vagrant dir from host machine
# --------------------
mkdir /vagrant/httpdocs
ln -fs /vagrant/httpdocs /usr/share/nginx/html/public

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
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              # With php5-fpm:
              fastcgi_pass unix:/var/run/php5-fpm.sock;
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
service php5-fpm restart

# Mysql
# --------------------
# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive
# Install MySQL quietly
apt-get -q -y install mysql-server-5.5


SQL=$(cat <<EOF

[client]
port            = 3306
socket          = /var/run/mysqld/mysqld.sock

[mysqld_safe]
socket          = /var/run/mysqld/mysqld.sock
nice            = 0

[mysqld]

user            = mysql
pid-file        = /var/run/mysqld/mysqld.pid
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
basedir         = /usr
datadir         = /var/lib/mysql
tmpdir          = /tmp
lc-messages-dir = /usr/share/mysql

### MyISAM #
key_buffer_size = 16M # keep it low if no myisam data
myisam-recover-options = FORCE,BACKUP

### SAFETY #
innodb = force
max_allowed_packet = 150M
max_connect_errors = 100000
bind-address = 127.0.0.1
skip-name-resolve

### LANGUAGE #
init_connect='SET collation_connection = utf8_unicode_ci'
init_connect='SET NAMES utf8'
character-set-server=utf8
collation-server=utf8_unicode_ci
skip-character-set-client-handshake

### CACHES AND LIMITS #
back_log = 200
interactive_timeout = 7200
wait_timeout = 7200
net_read_timeout = 120
net_write_timeout = 300
sort_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 16M
join_buffer_size = 4M
tmp_table_size = 128M
max_heap_table_size = 128M
query_cache_type = 1
query_cache_size = 128M
query_cache_limit = 4M
max_connections = 150
thread_cache_size= 32
open_files_limit = 65535
table_definition_cache = 4000
table_open_cache = 4000

### INNODB_ #
innodb_thread_concurrency = 0
innodb_lock_wait_timeout = 7200
innodb_flush_method = O_DIRECT
innodb_log_files_in_group = 2
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table = 1
innodb_io_capacity = 400
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_buffer_pool_instances = 8
innodb_buffer_pool_size = 4G

### LOGGING #
log_error = /var/log/mysql/error.log
#log_queries_not_using_indexes = 1
#slow_query_log_file = /var/lib/mysql/mysql-slow.log

### BINARY LOGGING #
#log_bin = /var/lib/mysql/mysql-bin
#expire_logs_days = 14
#sync_binlog = 1

EOF
)


echo "$SQL" > /etc/mysql/my.cnf


mysql -u root -e "CREATE DATABASE IF NOT EXISTS magentodb"
mysql -u root -e "GRANT ALL PRIVILEGES ON magentodb.* TO 'magentouser'@'localhost' IDENTIFIED BY 'password'"
mysql -u root -e "FLUSH PRIVILEGES"


# Magento
# --------------------
# http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/installing_magento_via_shell_ssh

# Download and extract
if [[ ! -f "/vagrant/httpdocs/index.php" ]]; then
  cd /vagrant/httpdocs
  wget http://www.magentocommerce.com/downloads/assets/${MAGE_VERSION}/magento-${MAGE_VERSION}.tar.gz
  tar -zxvf magento-${MAGE_VERSION}.tar.gz
  mv magento/* magento/.htaccess .
  chmod -R o+w media var
  chmod o+w app/etc
  # Clean up downloaded file and extracted dir
  rm -rf magento*
fi


# Sample Data
if [[ $SAMPLE_DATA == "true" ]]; then
  cd /vagrant

  if [[ ! -f "/vagrant/magento-sample-data-${DATA_VERSION}.tar.gz" ]]; then
    # Only download sample data if we need to
    wget http://www.magentocommerce.com/downloads/assets/${DATA_VERSION}/magento-sample-data-${DATA_VERSION}.tar.gz
  fi

  tar -zxvf magento-sample-data-${DATA_VERSION}.tar.gz
  cp -R magento-sample-data-${DATA_VERSION}/media/* httpdocs/media/
  cp -R magento-sample-data-${DATA_VERSION}/skin/*  httpdocs/skin/
  mysql -u root magentodb < magento-sample-data-${DATA_VERSION}/magento_sample_data_for_${DATA_VERSION}.sql
  rm -rf magento-sample-data-${DATA_VERSION}
fi


# Run installer
if [ ! -f "/vagrant/httpdocs/app/etc/local.xml" ]; then
  cd /vagrant/httpdocs
  sudo /usr/bin/php -f install.php -- --license_agreement_accepted yes \
  --locale en_US --timezone "America/Sao_Paulo" --default_currency USD \
  --db_host localhost --db_name magentodb --db_user magentouser --db_pass password \
  --url "http://127.0.0.1:8080/" --use_rewrites yes \
  --use_secure no --secure_base_url "http://127.0.0.1:8080/" --use_secure_admin no \
  --skip_url_validation yes \
  --admin_lastname Owner --admin_firstname Store --admin_email "krishna@agentelinux.com.br" \
  --admin_username admin --admin_password password123123
  /usr/bin/php -f shell/indexer.php reindexall
fi

# Install n98-magerun
# --------------------
cd /vagrant/httpdocs
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
