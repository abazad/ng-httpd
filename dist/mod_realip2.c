/*
* mod_realip2
* Olexander Shtepa
* Changelog:
*  1.1 - Move the `realip2_post_read_request' handler from being APR_HOOK_MIDDLE to
         APR_HOOK_FIRST to make the module run before modules like mod_geoip. (from mod_rpaf)
*  1.0 - Initial release.
*/

#include <string.h>
#include <arpa/inet.h>

#include "httpd.h"
#include "http_config.h"
#include "http_protocol.h"

#include "apr_pools.h"
#include "apr_strings.h"
#include "apr_tables.h"

#define REALIP2_STATUS_UNDEFINED 0
#define REALIP2_STATUS_ON        1
#define REALIP2_STATUS_OFF       2

#ifdef REALIP2_VERSION_SHOW
# define REALIP2_VERSION "1.1"
#endif


static const char* realip2_default_header="X-Real-IP";

module AP_MODULE_DECLARE_DATA realip2_module;

typedef struct
{
	int status;
	apr_array_header_t* proxy_addrs;
	const char* header;
} realip2_server_cfg;

static int realip2_match_proxy(const request_rec* r, const realip2_server_cfg* cfg)
{
	int i;
	int nelts=cfg->proxy_addrs->nelts;
	const apr_sockaddr_t** proxy_addrs=(const apr_sockaddr_t**)cfg->proxy_addrs->elts;
	const apr_sockaddr_t*  remote_addr=r->connection->remote_addr;

	for(i=0;i<nelts;++i)
		if (apr_sockaddr_equal(remote_addr,proxy_addrs[i]))
			return 1;

	return 0;
}

static void realip2_replace_ip(request_rec* r, const char* new_ip)
{
	struct in_addr sin_addr;
#if APR_HAVE_IPV6
	struct in6_addr sin6_addr;
#endif
	apr_sockaddr_t* remote_addr=r->connection->remote_addr;

	if (inet_pton(APR_INET,new_ip,&sin_addr)>0)
	{
#if APR_HAVE_IPV6
		if (remote_addr->family==APR_INET6)
		{
			remote_addr->family=APR_INET;
			remote_addr->salen=sizeof(struct sockaddr_in);
			remote_addr->addr_str_len=16;
			remote_addr->ipaddr_len=sizeof(struct in_addr);
			remote_addr->ipaddr_ptr=&remote_addr->sa.sin.sin_addr;

			memset(&remote_addr->sa,0,sizeof(struct sockaddr_in));
			remote_addr->sa.sin.sin_family=APR_INET;
			remote_addr->sa.sin.sin_port=htons(remote_addr->port);
		}
#endif
		remote_addr->sa.sin.sin_addr.s_addr=sin_addr.s_addr;
	}
#if APR_HAVE_IPV6
	else if (inet_pton(APR_INET6,new_ip,&sin6_addr)>0)
	{
		if (remote_addr->family==APR_INET)
		{
			remote_addr->family=APR_INET6;
			remote_addr->salen=sizeof(struct sockaddr_in6);
			remote_addr->addr_str_len=46;
			remote_addr->ipaddr_len=sizeof(struct in6_addr);
			remote_addr->ipaddr_ptr=&remote_addr->sa.sin6.sin6_addr;

			memset(&remote_addr->sa,0,sizeof(struct sockaddr_in6));
			remote_addr->sa.sin6.sin6_family=APR_INET6;
			remote_addr->sa.sin6.sin6_port=htons(remote_addr->port);
		}
		memcpy(&remote_addr->sa.sin6.sin6_addr,&sin6_addr,sizeof(struct in6_addr));
	}
#endif
	else
		/* The new IP address does not valid */
		return;
	r->connection->remote_ip=apr_pstrdup(remote_addr->pool,new_ip);
}

static int realip2_post_read_request(request_rec* r)
{
	const realip2_server_cfg* cfg=(realip2_server_cfg*)ap_get_module_config(r->server->module_config,&realip2_module);

	if (cfg->status==REALIP2_STATUS_ON && realip2_match_proxy(r,cfg))
	{
		const char* real_ip=apr_table_get(r->headers_in,cfg->header);
		if (real_ip)
			realip2_replace_ip(r,real_ip);
	}

	return DECLINED;
}

#ifdef REALIP2_VERSION_SHOW
static int realip2_post_config(apr_pool_t* pconf, apr_pool_t* plog, apr_pool_t* ptemp, server_rec* s)
{
	ap_add_version_component(pconf,"mod_realip2/" REALIP2_VERSION);
	return OK;
}
#endif

static void* realip2_create_server_config(apr_pool_t* p, server_rec* s)
{
	realip2_server_cfg* cfg=(realip2_server_cfg*)apr_palloc(p,sizeof(realip2_server_cfg));

	cfg->status=REALIP2_STATUS_UNDEFINED;
	cfg->proxy_addrs=apr_array_make(p,0,sizeof(apr_sockaddr_t*));
	cfg->header=realip2_default_header;

	return (void*)cfg;
}

static void* realip2_merge_server_config(apr_pool_t* p, void* def_cfg, void* new_cfg)
{
	realip2_server_cfg* def=(realip2_server_cfg*)def_cfg;
	realip2_server_cfg* new=(realip2_server_cfg*)new_cfg;
	realip2_server_cfg* cfg=(realip2_server_cfg*)apr_palloc(p,sizeof(realip2_server_cfg));

	cfg->status=(new->status==REALIP2_STATUS_UNDEFINED)?def->status:new->status;
	cfg->proxy_addrs=apr_is_empty_array(new->proxy_addrs)?def->proxy_addrs:new->proxy_addrs;
	cfg->header=(new->header==realip2_default_header)?def->header:new->header;

	return (void*)cfg;
}

static const char* realip2_set_realip(cmd_parms* cmd, void* mconfig, int value)
{
	realip2_server_cfg* cfg=(realip2_server_cfg*)ap_get_module_config(cmd->server->module_config,&realip2_module);

	cfg->status=value?REALIP2_STATUS_ON:REALIP2_STATUS_OFF;

	return NULL;
}

static const char* realip2_set_realipproxy(cmd_parms* cmd, void* mconfig, const char* host)
{
	apr_status_t err;
	realip2_server_cfg* cfg=(realip2_server_cfg*)ap_get_module_config(cmd->server->module_config,&realip2_module);
	apr_sockaddr_t** new_host=apr_array_push(cfg->proxy_addrs);

	/* Resolve host */
	err=apr_sockaddr_info_get(new_host,host,APR_UNSPEC,0,0,cmd->pool);
	if (err!=APR_SUCCESS)
		return apr_pstrcat(cmd->pool,"Cannot resolve host name: ",host,NULL);

	/* Add all aditional addresses */
	while((*new_host)->next)
	{
		apr_sockaddr_t* next=(*new_host)->next;
		new_host=apr_array_push(cfg->proxy_addrs);
		*new_host=next;
	}

	return NULL;
}

static const char* realip2_set_realipheader(cmd_parms* cmd, void* mconfig, const char* header)
{
	realip2_server_cfg* cfg=(realip2_server_cfg*)ap_get_module_config(cmd->server->module_config,&realip2_module);

	cfg->header=header;

	return NULL;
}

static const command_rec realip2_cmds[]=
{
	AP_INIT_FLAG(
		"RealIP",
		realip2_set_realip,
		NULL,
		RSRC_CONF,
		"Enable remote IP rewriting by a real value"
	),
	AP_INIT_ITERATE(
		"RealIPProxy",
		realip2_set_realipproxy,
		NULL,
		RSRC_CONF,
		"Set hosts that can rewrite a real remote IP"
	),
	AP_INIT_TAKE1(
		"RealIPHeader",
		realip2_set_realipheader,
		NULL,
		RSRC_CONF,
		"Watch this header for a real IP value"
	),
	{NULL}
};

static void realip2_register_hooks(apr_pool_t* p)
{
#ifdef REALIP2_VERSION_SHOW
	ap_hook_post_config(realip2_post_config,NULL,NULL,APR_HOOK_MIDDLE);
#endif
	ap_hook_post_read_request(realip2_post_read_request,NULL,NULL,APR_HOOK_FIRST);
}

module AP_MODULE_DECLARE_DATA realip2_module=
{
	STANDARD20_MODULE_STUFF,
	NULL,
	NULL,
	realip2_create_server_config,
	realip2_merge_server_config,
	realip2_cmds,
	realip2_register_hooks,
};
