/* cidr_entries table creation
 *
 * $Id$
 */

/** This table contains CIDRs (and ACL/Key references) used in server 
     in various contexts.  **/

CREATE TABLE cidr_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
				      0=acls
				      1=server (allow-transfer),
				      2=zone (allow-update),
				      3=zone (masters),
				      4=zone (allow-query), 
				      5=zone (allow-transfer), 
				      6=zone (also-notify),
				      7=server (allow-query), 
				      8=server (allow-recursion), 
				      9=server (blackhole),
				      10=server (listen-on), 
				      11=server (forwarders),
				      12=zone (forwarders),
				      13=reserved */
        ref	    INT4 NOT NULL, /* ptr to table speciefied by type field
					-->acls.id
					-->servers.id
					-->zones.id  */
	mode	    INT4 DEFAULT 0, /* rule mode flag:
						0 = CIDR/IP
						1 = ACL
						2 = Key */
	ip	    CIDR,            /* CIDR value */
	acl	    INT4 DEFAULT -1, /* ptr to acls table record (ACL):
					-->acls.id */
	tkey	    INT4 DEFAULT -1, /* ptr to keys table record (Key):
					-->keys.id */
	op	    INT4 DEFAULT 0, /* rule operand:
					0 = none,
					1 = NOT */ 
	comment     TEXT
);

