#!/bin/bash -e

PHP_VERSION=${PHP_VERSION:=7.2}
MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:=YourStrong!Passw0rd}"

if [ `rpm -qa | grep -e "^httpd-2" | wc -l` -eq 0 ]; then
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

if [ `rpm -qa | grep "php-fpm" | wc -l` -eq 0 ]; then
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

	sudo dnf install -y php-devel unixODBC-devel

	sudo pecl channel-update pecl.php.net
	if [ `sudo pecl list | grep sqlsrv | grep -v grep  | wc -l` -eq 0 ]; then
	    sudo pecl install sqlsrv-5.8.1
	    sudo pecl install pdo_sqlsrv-5.8.1
	fi

	sudo dnf remove -y php-devel unixODBC-devel

	PHP_EXT_DIR=`php --ini | grep "Scan for additional .ini files" | sudo sed -e "s|.*:\s*||"`
	if [ `grep pdo_sqlsrv ${PHP_EXT_DIR}/30-pdo_sqlsrv.ini 2> /dev/null | grep -v grep | wc -l` -eq 0 ]; then
	    echo extension=pdo_sqlsrv >> ${PHP_EXT_DIR}/30-pdo_sqlsrv.ini
	    echo extension=sqlsrv >> ${PHP_EXT_DIR}/20-sqlsrv.ini
	fi

	echo Restarting PHP-FPM...
	sudo systemctl restart php-fpm

	echo Restarting Apache httpd...
	sudo systemctl restart httpd
fi

cat <<-'EOF' > /tmp/test-db-conn.php
    <?php
    $con=new PDO(
        "sqlsrv:Server=localhost,1433;Database=master",
        "sa",
        getenv("MSSQL_SA_PASSWORD")
    );
    $stmt=$con->prepare("SELECT @@Version as SQL_VERSION, CURRENT_TIMESTAMP as TIME");
    $stmt->execute();
    $stmt->setFetchMode(PDO::FETCH_ASSOC);
    var_dump($stmt->fetch());
EOF

php /tmp/test-db-conn.php
rm /tmp/test-db-conn.php

echo 'Done!'
