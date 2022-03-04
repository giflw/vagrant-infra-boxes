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
    echo Installing MS SQL Server PHP driver...
    if [ ! -f /etc/yum.repos.d/mssql-release.repo ]; then
        curl https://packages.microsoft.com/config/rhel/8/prod.repo | sudo tee /etc/yum.repos.d/mssql-release.repo > /dev/null
    fi
    sudo ACCEPT_EULA=Y yum install -y msodbcsql17

    echo Installing REMI repository...
    sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    sudo dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    sudo dnf -y module reset php

    echo Installing php ${PHP_VERSION}
    sudo dnf -y module install php:remi-${PHP_VERSION}

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
        php-sqlsrv \
        php-xml \
        php-zip

    echo Enabling php-fpm...
    echo '<?php phpinfo(); ?>' | sudo tee /var/www/html/info.php > /dev/null
    sudo systemctl enable --now php-fpm

    echo Installing MS SQL Server PHP driver...

    PHP_EXT_DIR=`php --ini | grep "Scan for additional .ini files" | sudo sed -e "s|.*:\s*||"`
    cat << EOF > ${PHP_EXT_DIR}/99-dev.ini
    display_errors = 1
    display_startup_errors = 1
    error_reporting = E_ALL
EOF

    echo Installing Composer...
    sudo dnf -y install wget
    wget https://getcomposer.org/installer -O /tmp/composer-installer.php
    sudo php /tmp/composer-installer.php --filename=composer --install-dir=/usr/local/bin
    unlink /tmp/composer-installer.php

    if [ -z "`tr ':' ' ' <<< $PATH | xargs -n 1 echo | grep /usr/local/bin`" ]; then
        echo PATH=/usr/local/bin:$PATH > /etc/profile.d/path.sh
    fi

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
 