/* nets table creation
 *
 * Net/subnet descriptions, linked to server record. Used mainly for generating
 * subnet map for DHCP and access control/user friendliness in front-ends. 
 *
 * $Id$
 */

CREATE TABLE nets (
       id	   SERIAL,
       server	   INT4 NOT NULL,

       name	   TEXT,
       net	   CIDR NOT NULL,
       subnet      BOOL DEFAULT true,
       rp_mbox	   TEXT DEFAULT '.',
       rp_txt	   TEXT DEFAULT '.',
       no_dhcp     BOOL DEFAULT false, 
       range_start CIDR,
       range_end   CIDR,
       comment	   TEXT,

	/* dhcp	(dhcp_entries) */

       CONSTRAINT  nets_key PRIMARY KEY (net,server)
) INHERITS(pokemon);


