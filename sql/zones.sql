/* zones table creation
 *
 * table to store zone specific data 
 * (zone usually have bunch of host table records linked to it)
 *
 * $Id$
 */

/** This table contains zone definitions of a server. **/

CREATE TABLE zones (
       id	   SERIAL, /* unique ID */
       server	   INT4 NOT NULL, /* ptr to a record in servers table
					-->servers.id */

       active	   BOOL DEFAULT true,  /* zone active flag 
					 (only active zones are included in
					  named configuration) */
       dummy	   BOOL DEFAULT false, /* dummy zone flag */
       type	   CHAR(1) NOT NULL, /* zone type:
					(H)int, 
					(M)aster, 
					(S)lave, 
				        (F)orward */
       reverse	   BOOL DEFAULT false, /* true for reverse (arpa) zones */
       noreverse   BOOL DEFAULT false, /* if true, zone not used in reverse
				          map generation */
       nnotify	   CHAR(1) DEFAULT 'D', /* notify: D=default, Y=yes, N=no */
       chknames    CHAR(1) DEFAULT 'D', /* check-names:
					  D=default,W=warn,F=fail,I=ignore */
       class	   CHAR(2) DEFAULT 'in', /* zone class (IN) */
       name	   TEXT NOT NULL CHECK (name <> ''), /* zone name */
       hostmaster  TEXT, /* hostmaster (email)
			    (optional; if not defined value from server table
			     is used instead) */
       serial	   CHAR(10) DEFAULT '1999123001', /* zone serial number
						   (automagically updated) */
       refresh	   INT4,  /* zone SOA refresh time */
       retry	   INT4,  /* zone SOA retry time */
       expire	   INT4,  /* zone SOA expire time */
       minimum	   INT4,  /* zone SOA minimum (negative caching) time */
       ttl	   INT4,  /* default TTL for RRs in this zone 
			     (if not defined, value from servers record is
				used instead) */	
       zone_ttl	   INT4,  /* unused */
       comment	   TEXT, 

       reversenet  CIDR,  /* contains CIDR of the reverse zone
			    (if applicaple) */
       parent	   INT4 DEFAULT -1, /* unused */

       CONSTRAINT  zones_key PRIMARY KEY (name,server)
) INHERITS(common_fields);

