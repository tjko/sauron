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

	zones_only	BOOL DEFAULT false, /* if true, generate named.zones 
					       file otherwise generate 
					       complete named.conf */
	no_roots	BOOL DEFAULT false, /* if true, no root server (hint)
					       zone entry is generated */

	/* named.conf options...more to be added as needed... */
	directory	TEXT, /* base directory for named (optional) */
	pid_file	TEXT, /* pid-file pathname (optional) */
	dump_file	TEXT, /* dump-file pathname (optiona) */
	named_xfer	TEXT, /* named-xfer pathname (optional) */
	stats_file	TEXT, /* stats-file pathname (optional) */
	named_ca	TEXT, /* root servers filename */
	pzone_path	TEXT DEFAULT '',     /* relative path for master
					        zone files */
	szone_path	TEXT DEFAULT 'NS2/', /* relative path for slave 
						zone files */
	query_src_ip	TEXT,  /* query source ip (optional) (ip | '*') */ 
	query_src_port 	TEXT,  /* query source port (optional) (port | '*') */
	listen_on_port	TEXT,  /* listen on port (optional) */

	/* check-names: D=default, W=warn, F=fail, I=ignore */
	checknames_m	CHAR(1) DEFAULT 'D', /* check-names master */
	checknames_s	CHAR(1) DEFAULT 'D', /* check-names slave */
	checknames_r	CHAR(1) DEFAULT 'D', /* check-names response */

	/* boolean flags: D=default, Y=yes, N=no */
	nnotify		CHAR(1)	DEFAULT 'D', /* notify */
	recursion	CHAR(1) DEFAULT 'D', /* recursion */

	/* default TTLs */
	ttl		INT4 DEFAULT 86400,  /* default TTL for RR records */
	refresh		INT4 DEFAULT 43200,  /* default SOA refresh */
	retry		INT4 DEFAULT 3600,   /* default SOA retry */
	expire		INT4 DEFAULT 604800, /* default SOA expire */
	minimum		INT4 DEFAULT 86400,  /* default SOA minimum 
						(negative caching ttl) */


	/* defaults to use in zones */
	hostname	TEXT,  /* primary servername for sibling zone SOAs */
	hostmaster	TEXT,  /* hostmaster name for sibling zone SOAs
	                          unless overided in zone */

	comment		TEXT,
	
	CONSTRAINT	servers_name_key UNIQUE(name)
) INHERITS(common_fields);


