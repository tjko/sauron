/* servers table creation
 *
 * table to store server specific data 
 * (server can have multiple zones linked to it) 
 *
 * $Id$
 */

CREATE TABLE servers ( 
	id		SERIAL PRIMARY KEY,
	name		TEXT UNIQUE NOT NULL CHECK(name <> ''),

	zones_only	BOOL DEFAULT false, /* if true, generate named.zones 
					       file otherwise generate 
					       complete named.conf */
	no_roots	BOOL DEFAULT false, /* ? */

	/* named.conf options...more to be added as needed... */
	directory	TEXT,
	pid_file	TEXT,
	dump_file	TEXT,
	named_xfer	TEXT,
	stats_file	TEXT,
	named_ca	TEXT,
	pzone_path	TEXT DEFAULT '',
	szone_path	TEXT DEFAULT 'NS2/', 
	query_src_ip	TEXT,  /* ip | '*' */
	query_src_port 	TEXT,  /* port | '*' */
	listen_on_port	TEXT,

	/* check-names: D=default, W=warn, F=fail, I=ignore */
	checknames_m	CHAR(1) DEFAULT 'D', /* check-names master */
	checknames_s	CHAR(1) DEFAULT 'D', /* check-names slave */
	checknames_r	CHAR(1) DEFAULT 'D', /* check-names response */

	/* boolean flags: D=default, Y=yes, N=no */
	nnotify		CHAR(1)	DEFAULT 'D', /* notify */
	recursion	CHAR(1) DEFAULT 'D', /* recursion */

	/* default TTLs */
	ttl		INT4 DEFAULT 86400,
	refresh		INT4 DEFAULT 43200,
	retry		INT4 DEFAULT 3600,
	expire		INT4 DEFAULT 604800,
	minimum		INT4 DEFAULT 86400,


	/* defaults to use in zones */
	hostname	TEXT,  /* primary servername for sibling zone SOAs */
	hostmaster	TEXT,  /* hostmaster name for sibling zone SOAs
	                          unless overided in zone */

	comment		TEXT
	
       /* allow_transfer (cird_entries) */
       /* dhcp */
) INHERITS(pokemon);


