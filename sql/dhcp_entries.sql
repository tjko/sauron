/* dhcp_entries table creation
 *
 * This table contains DHCP options.      
 *
 * $Id$
 */

CREATE TABLE dhcp_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=server,2=zone,3=host,4=net,5=group */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field */
	dhcp	    TEXT,
        comment     TEXT
);

