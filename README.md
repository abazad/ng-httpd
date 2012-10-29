# Nginx frontend for DirectAdmin
This solution allows you to set up Nginx in front of Apache for all your DirectAdmin-driven virtual hosts. Any domain change made in DA panel will be automatically reflected* on Nginx vhost list.

\* ng-httpd control script operates once a minute via crontab, so note on slight delay in changes propagation

## Requirements
- [Debian-based] or [RHEL-based] linux distro
- [DirectAdmin] 1.37+

## Installation
Simply run as root:

	:::shell
	hg clone https://bitbucket.org/alexeyworld/ng-httpd
	cd ng-httpd && ./install.sh

## Management
You could easily on/off Nginx frontend in DA web interface `your-domain:2222/CMD_PLUGIN_MANAGER` using install/uninstall buttons.

There is no necessity to interact with control script normally. But if you really need, you could =) Call `/usr/local/nginx/sbin/ng-httpd.sh` with no arguments to get usage notes.

[Debian-based]: http://en.wikipedia.org/wiki/List_of_Linux_distributions#Debian-based
[RHEL-based]: http://en.wikipedia.org/wiki/List_of_Linux_distributions#Red_Hat_Enterprise_Linux-based
[DirectAdmin]: http://www.directadmin.com/
