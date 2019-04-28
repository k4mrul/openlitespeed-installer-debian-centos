#!/bin/bash

# Setting a log file
LOG="./openlitespeed-installation-log.txt"

# Get the server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

function isRoot () {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function checkOS () {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
        COMMAND="apt-get"
        VERSION=$VERSION_ID
        source /etc/os-release
            if [[ ! $VERSION_ID =~ (8|9) ]]; then
                echo -e "Your version of Debian is not supported by this script. Only debian 8 and 9 are supported.\n"
                exit 1
            fi
	elif [[ -e /etc/fedora-release ]]; then
		OS=fedora
        COMMAND="yum"
	elif [[ -e /etc/centos-release ]]; then
        if ! grep -qs "^CentOS Linux release 7" /etc/centos-release; then
                echo "The script only support CentOS 7. You version of CentOS is not 7"
                exit 1
        fi
		OS=centos
        COMMAND="yum"
	else
		echo "Currently this script works only on Debian 8/9 and CentOS 7 Linux system. Looks like your OS is none of them"
		exit 1
	fi
}

function initialCheck () {
	if ! isRoot; then
		echo "You need to run this script as root"
		exit 1
	fi
	checkOS
}

function updateSystem() {
    $COMMAND update -y
    $COMMAND install sudo -y
    $COMMAND install wget -y
    $COMMAND install build-essential -y
    $COMMAND install policycoreutils-python* -y
    $COMMAND install rcs libpcre3-dev libexpat1-dev libssl-dev libgeoip-dev libudns-dev zlib1g-dev libxml2 libxml2-dev libpng-dev openssl -y
}

function enableRepo() {
    if [[ "$OS" == "debian" ]]; then
        wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash
        apt-get install software-properties-common dirmngr -y
        export DEBIAN_FRONTEND=noninteractive
        if [[ "$VERSION" == 8 ]]; then
            apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
            add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://mariadb.biz.net.id/repo/10.3/debian jessie main' -y
        else
            apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xF1656F24C74CD1D8
            add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://mirror.zol.co.zw/mariadb/repo/10.3/debian stretch main' -y
        fi
    else
        rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el7.noarch.rpm
        cat > /etc/yum.repos.d/mariadb.repo << EOL
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.3/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOL
        yum clean all
    fi
}

function installOpenLiteSpeedAndPHP () {
    $COMMAND install openlitespeed -y
    $COMMAND install lsphp73 lsphp73-common lsphp73-curl lsphp73-mysql lsphp73-imap lsphp73-imap  lsphp73-json lsphp73-opcache  lsphp73-tidy lsphp73-recode lsphp73-memcached memcached -y
}

function allowFirewall () {
    if [[ "$OS" == "debian" ]]; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8088/tcp
        ufw allow 7080/tcp
        ufw reload
    else
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=8088/tcp
        firewall-cmd --permanent --add-port=7080/tcp
        firewall-cmd --reload
    fi
}

function tweakPHP () {
    if [[ "$OS" == "debian" ]]; then
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/g' /usr/local/lsws/lsphp73/etc/php/7.3/litespeed/php.ini
        sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /usr/local/lsws/lsphp73/etc/php/7.3/litespeed/php.ini
        sed -i 's/post_max_size = 8M/post_max_size = 100M/g' /usr/local/lsws/lsphp73/etc/php/7.3/litespeed/php.ini
        sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /usr/local/lsws/lsphp73/etc/php/7.3/litespeed/php.ini

    else
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/g' /usr/local/lsws/lsphp73/etc/php.ini
        sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /usr/local/lsws/lsphp73/etc/php.ini
        sed -i 's/post_max_size = 8M/post_max_size = 100M/g' /usr/local/lsws/lsphp73/etc/php.ini
        sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /usr/local/lsws/lsphp73/etc/php.ini
    fi
    /usr/local/lsws/bin/lswsctrl restart
}

function installMariadb () {
    $COMMAND update
    $COMMAND install mariadb-server -y
    systemctl enable mariadb
    systemctl restart mariadb
}



# If someone interrupt the script
trap cleanup SIGINT

cleanup()
{
  rm -f ./openlitespeed-installation-log.txt
  exit 1
}


# Main script execution start

initialCheck

echo "==================Updating system==========================="
{
    updateSystem
    enableRepo
} &>> $LOG
sleep 1
echo ""

echo "==================Installing OpenLiteSpeed with PHP 7.3 and required dependencies==========================="
{
    installOpenLiteSpeedAndPHP
} &>> $LOG
sleep 1
echo ""

echo "==================Allowing firewall==========================="
{
    allowFirewall
} &>> $LOG
sleep 1
echo ""

echo "==================Tweaking PHP==========================="
{
    tweakPHP
} &>> $LOG
sleep 1
echo ""

echo "==================Installing MariaDB 10.3==========================="
{
    installMariadb
} &>> $LOG
sleep 1
echo ""

echo "Set mysql root password......"
sleep 2
mysql_secure_installation
sleep 1
echo ""

echo -e "\n\n=================>OpenLiteSpeed has been successfully installed<=========================="
echo ""
echo "Open web browser and browse http://$SERVER_IP:7080/ and enter admin:123456 as login (don't forget to change the credentials from 'Webadmin Settings')."
echo -e "\n\nThank you for using this script :) \n\n"
