#!/bin/bash
cmd=$1
user=$2
domain=$3

NGCONFDIR=/usr/local/nginx/conf
DAUSERDIR=/usr/local/directadmin/data/users

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

del() {
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

usage() {
	echo "Usage:"
	echo "$0 build"
	echo "$0 add user domain"
	echo "$0 del user [domain]"
}

case $cmd in
	"add"	) add;;
	"del"	) del;;
	"build"	) build;;
	*		) usage;;
esac
