/* cidr_entries table creation
 *
 * This table contains CIDRs used in server various contexts.      
 *
 * $Id$
 */

CREATE TABLE cidr_entries (
	id	    SERIAL PRIMARY KEY,
	type        INT4 NOT NULL, /* 1=server (allow_transfer)
				      2=zone (allow_update)
				      3=zone (masters) */
        ref	    INT4 NOT NULL, /* ptr to table speciefied by type field */
	ip	    CIDR,
	comment     TEXT
);

