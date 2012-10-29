#!/bin/bash
CURDIR=$(cd $(dirname "$0"); pwd)
PREFIX=/usr/local/nginx
LATEST=1.0.11
OK='\033[01;32m'
DO='\033[01;35m'
ER='\033[01;31m'
RS='\033[0m'

vercomp() {
	if [ $1 == $2 ]; then
		return 0
	fi
	local gt=$(echo -e "$1\n$2" | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1)
	if [ $gt == $1 ]; then
		return 1
	fi
	return 2
}

checklatest() {
	if [ ! -f $PREFIX/sbin/nginx ]; then
		return 1
	fi
	local current=$($PREFIX/sbin/nginx -v 2>&1 | egrep -o '[0-9]+(\.[0-9]+)+')
	vercomp $current $LATEST
	if [ $? == 2 ]; then
		return 2
	fi
	return 0
}

echo -ne "Checking for distribution system "
if [ -f /etc/debian_version ]; then
DISTRO="debian"
elif [ -f /etc/redhat-release ]; then
DISTRO="redhat"
else
echo -e "[$ER unsupported $RS]"
exit 1
fi
echo -e "[$OK $DISTRO $RS]"

echo -ne "Checking for DirectAdmin installed "
if [ -f /usr/local/directadmin/directadmin ]; then
	echo -e "[$OK OK $RS]"
else
	echo -e "[$ER NO $RS]"
	exit 1
fi

checklatest
E=$?
echo -ne "Checking for latest Nginx version "
if [ $E == 0 ]; then
	echo -e "[$OK OK $RS]"
else
	echo -e "[$DO NO $RS]"
	echo -ne "Downloading Nginx source "
	cd /usr/local/src
	rm -rf nginx*
	nglatest=nginx-$LATEST
	wget -q -t 1 -T 5 http://nginx.org/download/$nglatest.tar.gz
	if [ $? != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
	tar -xzf $nglatest.tar.gz
	cd $nglatest
	./configure --with-http_ssl_module && make
	E=$?
	echo -ne "Building Nginx binary "
	if [ $E != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
	make install
	E=$?
	echo -ne "Installing Nginx "
	if [ $E != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
fi

cd $CURDIR
cp initrc-$DISTRO /etc/init.d/nginx
chmod 750 /etc/init.d/nginx
if [ $DISTRO == "debian" ]; then
	update-rc.d nginx defaults > /dev/null
elif [ $DISTRO == "redhat" ]; then
	chkconfig --add nginx && chkconfig nginx on
fi
E=$?
echo -ne "Creating Nginx init script "
if [ $E != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"

av=$(/usr/sbin/httpd -v | egrep -o '[0-9]+(\.[0-9]+)+')
E=$?
echo -ne "Checking Apache version "
if [ $E == 0 ]; then
	echo -e "[$OK $av $RS]"
else
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
vercomp $av 2.4
if [ $? == 2 ]; then
	ac=22
	echo -ne "Checking for mod_realip2 installed "
	if [ -f /usr/lib/apache/mod_realip2.so ]; then
		echo -e "[$OK OK $RS]"
	else
		echo -e "[$DO NO $RS]"
		cd $CURDIR/dist
		apxs -ci mod_realip2.c
		E=$?
		echo -ne "Installing mod_realip2 "
		if [ $E != 0 ]; then
			echo -e "[$ER FAIL $RS]"
			exit 1
		fi
		echo -e "[$DO DONE $RS]"
	fi
else
	ac=24
fi

echo -ne "Enabling extra config "
cd /etc/httpd/conf
sed -i -e /rpaf/Id -e /realip/Id -e /remoteip/Id -e /httpd-ng/d httpd.conf
echo "Include conf/extra/httpd-ng.conf" >> httpd.conf
if [ $? != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"

echo -ne "Copying new files "
cd $CURDIR
cp -f httpd-ng-$ac.conf /etc/httpd/conf/extra/httpd-ng.conf
cp -f ng-httpd.sh $PREFIX/sbin/
chmod 755 $PREFIX/sbin/ng-httpd.sh
cp -f conf/* $PREFIX/conf/
mkdir -p $PREFIX/conf/extra
$PREFIX/sbin/ng-httpd.sh queue
cp -f logrotate /etc/logrotate.d/nginx
mkdir -p /usr/local/directadmin/plugins/ng-httpd
cp -Rf plugin/* /usr/local/directadmin/plugins/ng-httpd/
chown -R diradmin:diradmin /usr/local/directadmin/plugins/ng-httpd
chmod 755 /usr/local/directadmin/plugins/ng-httpd/scripts/*.sh
echo -e "[$DO DONE $RS]"

(crontab -l | sed /ng-httpd/d; echo "* * * * * $PREFIX/sbin/ng-httpd.sh queue") | crontab -
E=$?
echo -ne "Installing crontab "
if [ $E != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"

$PREFIX/sbin/ng-httpd.sh enable
E=$?
echo -ne "Enabling nginx frontend "
sed -i /nginx/d /usr/local/directadmin/data/admin/services.status
echo "nginx=ON" >> /usr/local/directadmin/data/admin/services.status
if [ $E != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"
