/* cidr_entries table creation
 *
 * $Id$
 */

/** This table contains CIDRs used in server various contexts.  **/

CREATE TABLE cidr_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
				      1=server (allow-transfer)
				      2=zone (allow-update)
				      3=zone (masters) 
				      4=zone (allow-query) 
				      5=zone (allow-transfer) 
				      6=zone (also-notify) 
				      7=server (allow-query) 
				      8=server (allow-recursion) 
				      9=server (blackhole) 
				      10=server (listen-on) 
				      11=zone (forwarders) */
        ref	    INT4 NOT NULL, /* ptr to table speciefied by type field
					-->servers.id
					-->zones.id  */
	ip	    CIDR, /* CIDR value */
	comment     TEXT
);

