#!/bin/bash -e

PHP_VERSION=${PHP_VERSION:=7.2}
MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:=YourStrong!Passw0rd}"

if [ -z "`rpm -qa httpd`" ]; then
    echo Installing Apache httpd
    sudo dnf install -y @httpd

    echo Enabling Apache httpd
    sudo systemctl enable --now httpd

    echo Configuring firewall...
    firewalld_status=`ps aux | grep firewall | grep -v grep | wc -l`
    sudo systemctl start firewalld
    sudo firewall-cmd --permanent --add-service={http,https}
    sudo firewall-cmd --reload
    if [ $firewalld_status -eq 0 ]; then
        sudo systemctl stop firewalld
    fi
fi

if [ -z "`rpm -qa php-fpm`" ]; then
    echo Installing php ${PHP_VERSION}
    sudo dnf -y module install php:${PHP_VERSION}

    echo Installing php extensions
    sudo dnf -y install \
        php-gd \
        php-intl \
        php-json \
        php-ldap \
        php-mbstring \
        php-opcache \
        php-pdo \
        php-pear \
        php-pdo \
        php-xml \
        php-zip

    echo Enabling php-fpm...
    echo '<?php phpinfo(); ?>' | sudo tee > /var/www/html/info.php
    sudo systemctl enable --now php-fpm

    echo Installing MS SQL Server PHP driver...

    sudo dnf install -y php-devel unixODBC unixODBC-devel

    sudo pecl channel-update pecl.php.net
    if [ `sudo pecl list | grep sqlsrv | grep -v grep  | wc -l` -eq 0 ]; then
        sudo pecl install sqlsrv-5.8.1
        chmod +x /usr/lib64/php/modules/sqlsrv.so
        sudo pecl install pdo_sqlsrv-5.8.1
        chmod +x /usr/lib64/php/modules/pdo_sqlsrv.so
    fi

    sudo dnf remove -y php-devel unixODBC-devel

    PHP_EXT_DIR=`php --ini | grep "Scan for additional .ini files" | sudo sed -e "s|.*:\s*||"`
    if [ `grep pdo_sqlsrv ${PHP_EXT_DIR}/30-pdo_sqlsrv.ini 2> /dev/null | grep -v grep | wc -l` -eq 0 ]; then
        echo extension=pdo_sqlsrv >> ${PHP_EXT_DIR}/30-pdo_sqlsrv.ini
        echo extension=sqlsrv >> ${PHP_EXT_DIR}/20-sqlsrv.ini
    fi

    cat << EOF > ${PHP_EXT_DIR}/99-dev.ini
    display_errors = 1
    display_startup_errors = 1
    error_reporting = E_ALL
EOF

    echo Restarting PHP-FPM...
    sudo systemctl restart php-fpm

    echo Restarting Apache httpd...
    sudo systemctl restart httpd

    echo "<?php phpinfo();" > /var/www/html/info.php

    if [ ! -f /var/www/html/test-db.php ]; then
        cat << EOF > /var/www/html/test-db.php
    <?php
    \$con = new PDO(
        "sqlsrv:Server=localhost,1433;Database=master",
        "sa",
        "${MSSQL_SA_PASSWORD}"
    );
    \$stmt = \$con->prepare("SELECT @@Version as SQL_VERSION, CURRENT_TIMESTAMP as TIME");
    \$stmt->execute();
    \$stmt->setFetchMode(PDO::FETCH_ASSOC);
EOF

    php /var/www/html/test-db.php

    fi
fi

echo "$0 done!"
 