/* servers table creation
 *
 * table to store server specific data 
 * (server can have multiple zones linked to it) 
 *
 * $Id$
 */

/** This table contains servers that are managed with this system.
   For each server named/dhcpd/printer configuration files can be
   automagically generated from the database. **/

CREATE TABLE servers ( 
	id		SERIAL PRIMARY KEY, /* unique ID */
	name		TEXT NOT NULL CHECK(name <> ''), /* server name */
	lastrun		INT DEFAULT -1,       /* last time server (DNS)
						 configuration was generated */

	zones_only	BOOL DEFAULT false, /* if true, generate named.zones 
					       file otherwise generate 
					       complete named.conf */
	no_roots	BOOL DEFAULT false, /* if true, no root server (hint)
					       zone entry is generated */
	dhcp_mode	INT DEFAULT 1, /* DHCP subnet map creation mode:
						0 = use VLANs,
						1 = use networks */
	dhcp_flags	INT DEFAULT 0, /* DHCP option flags:
					0x01 = auto-generate domainnames
					0x02 = enable failover protocol */
	named_flags	INT DEFAULT 0, /* named option flags:
			      0x01 = access control from master (slave only)
			      0x02 = include also slave zones from master
				     (slave only)
			      0x04 = do NOT generate HINFO records
			      0x08 = do NOT generate WKS records */
	masterserver	INT DEFAULT -1, /* dynamically add slave zones
					   for all zones in master server */

	/* named.conf options...more to be added as needed... */
	version		TEXT, /* version string to display (optional) */
	directory	TEXT, /* base directory for named (optional) */
	pid_file	TEXT, /* pid-file pathname (optional) */
	dump_file	TEXT, /* dump-file pathname (optiona) */
	named_xfer	TEXT, /* named-xfer pathname (optional) */
	stats_file	TEXT, /* statistics-file pathname (optional) */
	memstats_file	TEXT, /* memstatistics-file pathname (optional) */
	named_ca	TEXT DEFAULT 'named.ca', /* root servers filename */
	pzone_path	TEXT DEFAULT '',     /* relative path for master
					        zone files */
	szone_path	TEXT DEFAULT 'NS2/', /* relative path for slave 
						zone files */
	query_src_ip	TEXT,  /* query source ip (optional) (ip | '*') */ 
	query_src_port 	TEXT,  /* query source port (optional) (port | '*') */
	listen_on_port	TEXT,  /* listen on port (optional) */
	transfer_source INET,  /* transfer-source (optional) */
	forward		CHAR(1) DEFAULT 'D', /* forward: D=default
	                                        O=only, F=first */
	/* check-names: D=default, W=warn, F=fail, I=ignore */
	checknames_m	CHAR(1) DEFAULT 'D', /* check-names master */
	checknames_s	CHAR(1) DEFAULT 'D', /* check-names slave */
	checknames_r	CHAR(1) DEFAULT 'D', /* check-names response */

	/* boolean flags: D=default, Y=yes, N=no */
	nnotify		CHAR(1)	DEFAULT 'D', /* notify */
	recursion	CHAR(1) DEFAULT 'D', /* recursion */
	authnxdomain	CHAR(1) DEFAULT 'D', /* auth-nxdomain */
	dialup		CHAR(1) DEFAULT 'D', /* dialup */
	multiple_cnames	CHAR(1) DEFAULT 'D', /* multiple-cnames */
	rfc2308_type1	CHAR(1) DEFAULT 'D', /* rfc2308-type1 */
	

	/* default TTLs */
	ttl		INT4 DEFAULT 86400,   /* default TTL for RR records */
	refresh		INT4 DEFAULT 43200,   /* default SOA refresh */
	retry		INT4 DEFAULT 3600,    /* default SOA retry */
	expire		INT4 DEFAULT 2419200, /* default SOA expire */
	minimum		INT4 DEFAULT 86400,   /* default SOA minimum 
						(negative caching ttl) */

	/* IPv6 */
	ipv6		TEXT, /* reserved */

	/* DHCP failover */
	df_port		INT DEFAULT 519,      /* listen port */
	df_max_delay	INT DEFAULT 60,	      /* max-response-delay */
	df_max_uupdates INT DEFAULT 10,	      /* max-unacked-updates */
	df_mclt		INT DEFAULT 3600,     /* mlct */
	df_split	INT DEFAULT 128,      /* split */
	df_loadbalmax	INT DEFAULT 3,	      /* load balance max seconds */

	/* defaults to use in zones */
	hostname	TEXT,  /* primary servername for sibling zone SOAs */
	hostaddr	INET,  /* primary server IP address */
	hostmaster	TEXT,  /* hostmaster name for sibling zone SOAs
	                          unless overided in zone */

	comment		TEXT,
	
	CONSTRAINT	servers_name_key UNIQUE(name)
) INHERITS(common_fields);


