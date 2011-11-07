#!/bin/bash
CURDIR=$(cd $(dirname "$0"); pwd)
NGLATEST="nginx-1.0.9"
OK='\033[01;32m'
DO='\033[01;35m'
ER='\033[01;31m'
RS='\033[0m'

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

echo -ne "Checking for Nginx installed "
if [ -f /usr/local/nginx/sbin/nginx ]; then
	echo -e "[$OK OK $RS]"
else
	echo -e "[$DO NO $RS]"
	echo -ne "Downloading Nginx source "
	cd /usr/local/src
	rm -rf nginx*
	wget -q -t 1 -T 5 http://nginx.org/download/nginx-$NGLATEST.tar.gz
	if [ $? != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
	tar -xzf $NGLATEST.tar.gz
	cd $NGLATEST
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
	update-rc.d nginx defaults
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

echo -ne "Enabling extra config "
cd /etc/httpd/conf
sed -i -e /rpaf/Id -e /realip/Id -e /httpd-ng/d httpd.conf
echo "Include conf/extra/httpd-ng.conf" >> httpd.conf
if [ $? != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"

echo -ne "Copying new files "
cd $CURDIR
cp -f httpd-ng.conf /etc/httpd/conf/extra/
cp -f ng-httpd.sh /usr/local/nginx/sbin/
chmod 755 /usr/local/nginx/sbin/ng-httpd.sh
cp -f conf/* /usr/local/nginx/conf/
mkdir -p /usr/local/nginx/conf/extra
/usr/local/nginx/sbin/ng-httpd.sh queue
mkdir -p /usr/local/directadmin/plugins/ng-httpd
cp -Rf plugin/* /usr/local/directadmin/plugins/ng-httpd/
chown -R diradmin:diradmin /usr/local/directadmin/plugins/ng-httpd
chmod 755 /usr/local/directadmin/plugins/ng-httpd/scripts/*.sh
echo -e "[$DO DONE $RS]"

(crontab -l | sed /ng-httpd/d; echo "* * * * * /usr/local/nginx/sbin/ng-httpd.sh queue") | crontab -
E=$?
echo -ne "Installing crontab "
if [ $E != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"

/usr/local/nginx/sbin/ng-httpd.sh enable
E=$?
echo -ne "Enabling nginx frontend "
sed -i /nginx/d /usr/local/directadmin/data/admin/services.status
echo "nginx=ON" >> /usr/local/directadmin/data/admin/services.status
if [ $E != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"
