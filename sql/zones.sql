/* zones table creation
 *
 * table to store zone specific data 
 * (zone usually have bunch of host table records linked to it)
 *
 * $Id$
 */

CREATE TABLE zones ( /* zone table; contains zones */
       id	   SERIAL,
       server	   INT4 NOT NULL,

       active	   BOOL DEFAULT true,
       dummy	   BOOL DEFAULT false,
       type	   CHAR(1) NOT NULL, /* (H)int, (M)aster, (S)lave, 
				        (F)orward, ... */
       reverse	   BOOL DEFAULT false, /* true for reverse (arpa) zones */
       noreverse   BOOL DEFAULT false, /* if true, zone not used in reverse
				          map generation */
       nnotify	   BOOL DEFAULT true,
       chknames    CHAR(1) DEFAULT 'W', /* (W)arn, (F)ail, (I)gnore */
       class	   CHAR(2) DEFAULT 'in',
       name	   TEXT NOT NULL CHECK (name <> ''),
       hostmaster  TEXT,
       serial	   CHAR(10) DEFAULT '1999123001',
       refresh	   INT4 DEFAULT 43200,
       retry	   INT4 DEFAULT 3600,
       expire	   INT4 DEFAULT 604800,
       minimum	   INT4 DEFAULT 86400,
       ttl	   INT4 DEFAULT -1,
       comment	   TEXT,

       reversenet  CIDR,
       parent	   INT4 DEFAULT -1,

       /* allow_update (cidr_entries) */
       /* masters (cidr_entries) */
       /* ns (ns_entries) */
       /* mx (mx_entries) */
       /* txt (txt_entries) */
       /* dhcp (dhcp_entries) */

       CONSTRAINT  zones_key PRIMARY KEY (name,server)
) INHERITS(pokemon);

