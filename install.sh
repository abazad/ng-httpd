#!/bin/bash
CURDIR=$(dirname $0)
NGLATEST="nginx-0.8.53"
RPLATEST="mod_rpaf-0.6"
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
	wget -q -t 1 -T 5 http://sysoev.ru/nginx/$NGLATEST.tar.gz
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

echo -ne "Checking for Nginx init script "
if [ -f /etc/init.d/nginx ]; then
	echo -e "[$OK OK $RS]"
else
	echo -e "[$DO NO $RS]"
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
fi

echo -ne "Checking for mod_rpaf installed "
if [ -f /usr/lib/apache/mod_rpaf-2.0.so ]; then
	echo -e "[$OK OK $RS]"
else
	echo -e "[$DO NO $RS]"
	echo -ne "Downloading mod_rpaf source "
	cd /usr/local/src
	rm -rf mod_rpaf*
	wget -q -t 1 -T 5 http://stderr.net/apache/rpaf/download/$RPLATEST.tar.gz
	if [ $? != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
	tar -xzf $RPLATEST.tar.gz
	cd $RPLATEST
	apxs -ci mod_rpaf-2.0.c
	E=$?
	echo -ne "Installing mod_rpaf "
	if [ $E != 0 ]; then
		echo -e "[$ER FAIL $RS]"
		exit 1
	fi
	echo -e "[$DO DONE $RS]"
fi

echo -ne "Updating mod_rpaf configuration "
ips=$(ifconfig | grep Bcast | awk 'BEGIN {FS = "[ \t:]+"; ORS=" "} {print $4}')
cd /etc/httpd/conf
cat > extra/httpd-rpaf.conf <<EOF
LoadModule rpaf_module /usr/lib/apache/mod_rpaf-2.0.so
RPAFenable On
RPAFsethostname On
RPAFproxy_ips $ips
RPAFheader X-Real-IP
EOF
if [ $? != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"
echo -ne "Enabling mod_rpaf "
sed -i /[rR][pP][aA][fF]/d httpd.conf
echo "Include conf/extra/httpd-rpaf.conf" >> httpd.conf
if [ $? != 0 ]; then
	echo -e "[$ER FAIL $RS]"
	exit 1
fi
echo -e "[$DO DONE $RS]"
