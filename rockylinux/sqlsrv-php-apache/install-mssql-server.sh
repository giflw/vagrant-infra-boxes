#!/bin/bash -e
# based on: https://docs.microsoft.com/pt-br/sql/linux/sample-unattended-install-redhat?view=sql-server-ver15

# dependencies:start
# based on: https://docs.microsoft.com/pt-br/sql/linux/quickstart-install-connect-red-hat?view=sql-server-ver15
# If not configured, install python2 and openssl10 using the following commands: 
sudo yum install -y python2
sudo yum install -y compat-openssl10
sudo alternatives --set python /usr/bin/python2
# dependencies:end

# Use the following variables to control your install:

# Password for the SA user (required)
MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:=YourStrong!Passw0rd}"

# Product ID of the version of SQL server you're installing
# Must be Evaluation, Developer, Express, Web, Standard, Enterprise or your 25 digit product key
# Defaults to developer
MSSQL_PID="${MSSQL_PID:=Developer}"

FIREWALL_ALLOW_MSSQL=${FIREWALL_ALLOW_MSSQL:=true}

# Install SQL Server Agent (recommended)
SQL_ENABLE_AGENT=${SQL_ENABLE_AGENT:=true}

# Install SQL Server Full Text Search (optional)
SQL_INSTALL_FULLTEXT=${SQL_INSTALL_FULLTEXT:=true}

# Create an additional user with sysadmin privileges (optional)
SQL_INSTALL_USER=${SQL_INSTALL_USER:=admin}
SQL_INSTALL_USER_PASSWORD=${SQL_INSTALL_USER_PASSWORD:=Admin123!}

test -n "$MSSQL_SA_PASSWORD" \
  && echo MSSQL_SA_PASSWORD was given \
  || echo MSSQL_SA_PASSWORD not given
echo MSSQL_PID: $MSSQL_PID
echo SQL_ENABLE_AGENT: $SQL_ENABLE_AGENT
echo SQL_INSTALL_FULLTEXT: $SQL_INSTALL_FULLTEXT
echo SQL_INSTALL_USER: $SQL_INSTALL_USER
test -n "$SQL_INSTALL_USER_PASSWORD" \
  && echo SQL_INSTALL_USER_PASSWORD was given \
  || echo SQL_INSTALL_USER_PASSWORD not given

if [ -z "$MSSQL_SA_PASSWORD" ]; then
  echo Environment variable MSSQL_SA_PASSWORD must be set for unattended install
  exit 1
fi

mssql_installed=1
if [ ! `which mssql-conf 2> /dev/null` ]; then
  mssql_installed=0
  echo Adding Microsoft repositories...
  sudo curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/8/mssql-server-2019.repo

  echo Installing SQL Server...
  sudo yum install -y mssql-server
fi

echo Running mssql-conf setup...
echo 'mssql_installed =' $mssql_installed
if [ $mssql_installed -eq 1 ]; then
  sudo systemctl stop mssql-server
fi
sudo MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD \
     MSSQL_PID=$MSSQL_PID \
     /opt/mssql/bin/mssql-conf -n setup accept-eula

if [ ! `which sqlcmd 2> /dev/null` ]; then
  echo Installing mssql-tools and unixODBC developer...
  sudo curl -o /etc/yum.repos.d/msprod.repo https://packages.microsoft.com/config/rhel/8/prod.repo
  sudo ACCEPT_EULA=Y yum install -y mssql-tools unixODBC-devel
fi

# Add SQL Server tools to the path by default:
echo Adding SQL Server tools to your path...
if [ ! -d '/etc/profile.d' ]; then
  mkdir /etc/profile.d
fi
if [ ! `grep '/opt/mssql-tools/bin:/opt/mssql/bin' /etc/profile.d/mssql-server.sh 2> /dev/null` ]; then
  echo PATH="$PATH:/opt/mssql-tools/bin:/opt/mssql/bin" >> /etc/profile.d/mssql-server.sh
  source /etc/profile.d/mssql-server.sh
fi

# Optional Enable SQL Server Agent :
echo SQL Server Agent enable=$SQL_ENABLE_AGENT...
sudo /opt/mssql/bin/mssql-conf set sqlagent.enabled $SQL_ENABLE_AGENT

# Optional SQL Server Full Text Search installation:
if [ "$SQL_INSTALL_FULLTEXT" = 'true' ]; then
  echo Installing SQL Server Full-Text Search...
  sudo yum install -y mssql-server-fts
else
  echo Removing SQL Server Full-Text Search...
  sudo yum remove -y mssql-server-fts
fi

# Configure firewall to allow TCP port 1433:
firewalld_status=`ps aux | grep firewall | grep -v grep | wc -l`
sudo systemctl start firewalld
if [ "$FIREWALL_ALLOW_MSSQL" = 'true' ]; then
  echo Configuring firewall to allow traffic on port 1433...
  sudo firewall-cmd --zone=public --add-port=1433/tcp --permanent
else
  echo Configuring firewall to deny traffic on port 1433...
  sudo firewall-cmd --zone=public --remove-port=1433/tcp --permanent
fi
sudo firewall-cmd --reload
if [ $firewalld_status -eq 0 ]; then
  sudo systemctl stop firewalld
fi

# Example of setting post-installation configuration options
# Set trace flags 1204 and 1222 for deadlock tracing:
#echo Setting trace flags...
sudo /opt/mssql/bin/mssql-conf traceflag 1204 1222 on

# Restart SQL Server after making configuration changes:
echo Restarting SQL Server...
sudo systemctl restart mssql-server

# Connect to server and get the version:
counter=1
errstatus=1
while [ $counter -le 5 ] && [ $errstatus = 1 ]; do
  echo -n Waiting for SQL Server to start...
  for i in `seq 1 5`; do
    sleep 1s
    echo -n .
  done
  echo ''
  /opt/mssql-tools/bin/sqlcmd \
    -S localhost \
    -U SA \
    -P $MSSQL_SA_PASSWORD \
    -Q "SELECT @@VERSION" 2>/dev/null
  errstatus=$?
  ((counter++))
done

# Display error if connection failed:
if [ $errstatus = 1 ]; then
  echo Cannot connect to SQL Server, installation aborted
  echo Error code $errstatus
  exit $errstatus
fi

# Optional new user creation:
if [ ! -z $SQL_INSTALL_USER ] && [ ! -z $SQL_INSTALL_USER_PASSWORD ]; then
  echo Creating user $SQL_INSTALL_USER
  /opt/mssql-tools/bin/sqlcmd \
    -S localhost \
    -U sa \
    -P $MSSQL_SA_PASSWORD \
    -Q "CREATE LOGIN [$SQL_INSTALL_USER] \
        WITH\
        PASSWORD=N'$SQL_INSTALL_USER_PASSWORD', \
        DEFAULT_DATABASE=[master], \
        CHECK_EXPIRATION=ON, \
        CHECK_POLICY=ON; \
        ALTER SERVER ROLE [sysadmin] ADD MEMBER [$SQL_INSTALL_USER]"
fi

echo Done!