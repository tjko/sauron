/* cidr_entries table creation
 *
 * $Id:$
 */

/** This table contains CIDRs (and ACL/Key references) used in server 
     in various contexts.  **/

CREATE TABLE cidr_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
				      0=acls
				      1=server (allow-transfer),  x
				      2=zone (allow-update),      X
				      3=zone (masters),           (iponly)
				      4=zone (allow-query),       X
				      5=zone (allow-transfer),    X
				      6=zone (also-notify),       (iponly)
				      7=server (allow-query),     x 
				      8=server (allow-recursion), x 
				      9=server (blackhole),       x
				      10=server (listen-on),      (cidronly)
				      11=server (forwarders),     (iponly)
				      12=zone (forwarders),       (iponly)
				      13=server (bind-globals),   
				      14=server (allow_query_cache), x
				      15=server (allow_notify),      x
				      */
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
	port	    INT,            /* port value, used by: forwarders */      
	comment     TEXT
) WITH OIDS;

CREATE INDEX cidr_entries_ref_index ON cidr_entries (type,ref);
CREATE INDEX cidr_entries_ip_index ON cidr_entries (ip);

