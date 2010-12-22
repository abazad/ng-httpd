#!/bin/bash
cmd=$1
user=$2
domain=$3

APCONFDIR=/etc/httpd/conf
NGCONFDIR=/usr/local/nginx/conf
DAROOTDIR=/usr/local/directadmin
DAUSERDIR=$DAROOTDIR/data/users
DATEMPDIR=$DAROOTDIR/data/templates
DAQUEUE=$DAROOTDIR/data/task.queue
TEMPLATES="virtual_host virtual_host_sub virtual_host_secure virtual_host_secure_sub \
	virtual_host2 virtual_host2_sub virtual_host2_secure virtual_host2_secure_sub \
	ips_virtual_host redirect_virtual_host"
EXTPORT=80
INTPORT=8888

add() {
	if [[ -z $user || -z $domain ]]; then
		usage
		exit 1
	fi

	userdir=$DAUSERDIR/$user
	if [ ! -d $userdir ]; then
		echo "User not found"
		exit 1
	fi

	domconf=$userdir/domains/$domain.conf
	if [ ! -f $domconf ]; then
		echo "Domain not found"
		exit 1
	fi

	ip=$(grep "ip=" $domconf | cut -d= -f2)
	ips=$ip
	if [ -f $userdir/domains/$domain.ip_list ]; then
		ips=$(cat $userdir/domains/$domain.ip_list)
	fi
	ssl=$(grep -ic "ssl=on" $domconf)
	pro=$(grep -ic "php=on|cgi=on" $domconf)

	alias=""
	pointer=""
	if [ -f $userdir/domains/$domain.pointers ]; then
		for ptr in $(cat $userdir/domains/$domain.pointers)
		do
			dom=$(echo $ptr | cut -d= -f1)
			type=$(echo $ptr | cut -d= -f2)
			if [ $type == "alias" ]; then
				alias="$alias.$dom "
			else
				pointer="$pointer $dom"
			fi
		done
	fi

	docroot=/home/$user/domains/$domain/public_html

	listen=""
	for ipp in $ips
	do
		listen="${listen}listen ${ipp}:80; "
	done

	sslconf=""
	if [ $ssl > 0 ]; then
		sslcert=$userdir/domains/$domain.cert
		sslkey=$userdir/domains/$domain.key
		if [ ! -f $sslcert ]; then
			sslcert=$(grep "apachecert=" /usr/local/directadmin/conf/directadmin.conf | cut -d= -f2)
			sslkey=$(grep "apachekey=" /usr/local/directadmin/conf/directadmin.conf | cut -d= -f2)
		fi
		sslconf="listen ${ip}:443 ssl; ssl_certificate $sslcert; ssl_certificate_key $sslkey;"
	fi

	proxy=""
	if [ $pro > 0 ]; then
		proxy="proxy_pass http://$ip:8888;"
	fi

	resconf=$NGCONFDIR/vhost/$user-$domain.conf

	sed -e s/ADDR/$ip/g -e s/DOMAIN/$domain/g -e s/ALIAS/"$alias"/g -e s/DOCROOT/"${docroot//\//\/}"/g \
		-e s/LISTEN/"$listen"/g -e s/PROXY/"${proxy//\//\/}"/g -e s/SSL/"${sslconf//\//\/}"/g \
		$NGCONFDIR/domain.conf > $resconf

	if [ -f $userdir/domains/$domain.subdomains ]; then
		for sub in $(cat $userdir/domains/$domain.subdomains)
		do
			subdocroot=$docroot/$sub
			subalias=""
			for als in $alias
			do
				subalias="$subalias .$sub$als"
			done
			sed -e s/ADDR/$ip/g -e s/DOMAIN/$sub.$domain/g -e s/ALIAS/"$subalias"/g -e s/DOCROOT/"${subdocroot//\//\/}"/g \
				-e s/LISTEN/"$listen"/g -e s/PROXY/"${proxy//\//\/}"/g -e s/SSL/"${sslconf//\//\/}"/g \
				$NGCONFDIR/domain.conf >> $resconf
		done
	fi

	for ptr in $pointer
	do
		sed -e s/DOMAIN/$domain/g -e s/POINTER/$ptr/g -e s/LISTEN/"$listen"/g \
			$NGCONFDIR/pointer.conf >> $resconf
	done
}

delete() {
	if [ -z $user ]; then
		usage
		exit 1
	fi

	if [ -n $domain ]; then
		rm -rf $NGCONFDIR/vhost/$user-*.conf
	else
		rm -rf $NGCONFDIR/vhost/$user-$domain.conf
	fi
}

build() {
	mkdir -p $NGCONFDIR/vhost
	rm -rf $NGCONFDIR/vhost/*

	for user in $(ls -1 $DAUSERDIR)
	do
		if [ ! -d $DAUSERDIR/$user ]; then
			continue
		fi

		for domain in $(cat $DAUSERDIR/$user/domains.list)
		do
			add $user $domain
		done
	done
}

updateips() {
	sed -i "s/:$EXTPORT/:$INTPORT/g" $APCONFDIR/ips.conf
	ips=$(cat $DAROOTDIR/data/admin/ip.list | awk 'BEGIN {FS = "[ \t:]+"; ORS=" "} {print $1}')
	cat > $APCONFDIR/extra/httpd-rpaf.conf <<EOF
LoadModule rpaf_module /usr/lib/apache/mod_rpaf-2.0.so
RPAFenable On
RPAFsethostname On
RPAFproxy_ips $ips
RPAFheader X-Real-IP
EOF
}

enable() {
	cd $DATEMPDIR
	mkdir -p custom

	for tpl in $TEMPLATES
	do
		if [ ! -f custom/$tpl.conf ]; then
			cp $tpl.conf custom/
		fi
		sed -i "s/:$EXTPORT/:$INTPORT/g" custom/$tpl.conf
	done

	echo "action=rewrite&value=ips" >> $DAQUEUE
	echo "action=rewrite&value=httpd" >> $DAQUEUE
	$DAROOTDIR/dataskq
	if [ $? != 0 ]; then
		echo "Apache config failed"
		exit 1
	fi

	updateips
	sed -i -e "s/$EXTPORT/$INTPORT/g" -e "/httpd-ssl/ s/^\s*#*\s*/#/" \
		-e "/httpd-rpaf/ s/^\s*#*\s*//" $APCONFDIR/httpd.conf
	echo "action=httpd&value=restart" >> $DAQUEUE
	$DAROOTDIR/dataskq
	if [ $? != 0 ]; then
		echo "Apache restart failed"
		exit 1
	fi

	sed -i "s/nginx=OFF/nginx=ON/" $DAROOTDIR/data/admin/services.status
	/etc/init.d/nginx start > /dev/null
	if [ $? != 0 ]; then
		echo "Nginx start failed"
		exit 1
	fi
}

disable() {
	sed -i "s/nginx=ON/nginx=OFF/" $DAROOTDIR/data/admin/services.status
	/etc/init.d/nginx stop > /dev/null
	if [ $? != 0 ]; then
		echo "Nginx stop failed"
		exit 1
	fi

	if [ -d $DATEMPDIR/custom ]; then
		cd $DATEMPDIR/custom

		for tpl in $TEMPLATES
		do
			if [ -f $tpl.conf ]; then
				sed -i "s/:$INTPORT/:$EXTPORT/g" $tpl.conf
			fi
		done
	fi

	sed -i -e "s/$INTPORT/$EXTPORT/g" -e "/httpd-ssl/ s/^\s*#*\s*//" \
		-e "/httpd-rpaf/ s/^\s*#*\s*/#/" $APCONFDIR/httpd.conf
	echo "action=rewrite&value=ips" >> $DAQUEUE
	echo "action=rewrite&value=httpd" >> $DAQUEUE
	echo "action=httpd&value=restart" >> $DAQUEUE
	$DAROOTDIR/dataskq
	if [ $? != 0 ]; then
		echo "Apache restart failed"
		exit 1
	fi
}

queue() {
	cd $(dirname $0)
	if [ ! -f queue ]; then
		touch queue
		chgrp diradmin queue
		chmod 664 queue
		exit 0
	fi

	while read line
	do
		$($0 $line)
	done < queue

	echo -n "" > queue
}

usage() {
	echo "Usage:"
	echo "$0 add user domain"
	echo "$0 delete user [domain]"
	echo "$0 (build|enable|disable|updateips|queue)"
}

case $cmd in
	"add"		) add;;
	"delete"	) delete;;
	"build"		) build;;
	"enable"	) enable;;
	"disable"	) disable;;
	"updateips"	) updateips;;
	"queue"		) queue;;
	*			) usage;;
esac
