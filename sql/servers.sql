/* servers table creation
 *
 * table to store server specific data 
 * (server can have multiple zones linked to it) 
 *
 * $Id$
 */

CREATE TABLE servers ( 
       id	   SERIAL PRIMARY KEY,
       name	   TEXT UNIQUE NOT NULL CHECK(name <> ''),

       zones_only  BOOL DEFAULT false, /* if true, generate named.zones file
			              otherwise generate complete named.conf */
       no_roots	   BOOL DEFAULT false,

	/* named.conf options...more to be added as needed... */
       directory      TEXT,
       named_ca	      TEXT,
       pzone_path     TEXT DEFAULT '',
       szone_path     TEXT DEFAULT 'NS2/', 

       hostname	      TEXT,  /* primary servername for sibling zone SOAs */
       hostmaster     TEXT,  /* hostmaster name for sibling zone SOAs
	                        unless overided in zone */

       comment	      TEXT
	
       /* allow_transfer (cird_entries) */
       /* dhcp */
) INHERITS(pokemon);


