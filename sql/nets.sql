/* nets table creation
 *
 * $Id$
 */

/** Net/subnet descriptions, linked to server record. 
    Used mainly for generating subnet map for DHCP and access 
    control/user friendliness in front-ends.  **/

CREATE TABLE nets (
       id	   SERIAL PRIMARY KEY, /* unique ID */
       server	   INT4 NOT NULL, /* ptr to a servers table record
					-->servers.id */

       netname     TEXT, /* (sub)net name */				
       name	   TEXT, /* descriptive name of the (sub)net */
       net	   CIDR NOT NULL, /* net CIDR */
       subnet      BOOL DEFAULT true,  /* subnet flag */
       dummy	   BOOL DEFAULT false, /* true for "dummy" subnets that are
					  group hosts inside real subnet */ 
       vlan	   INT4 DEFAULT -1, /* ptr to vlans table record
                                  -->vlans.id */
       alevel	   INT4 DEFAULT 0, /* required authorization level */
       type        INT4 DEFAULT 0, /* network type/option flags:
				      0x01 = private (hidden from browser) */
       ipv6        TEXT, /* reserved */
				  
       rp_mbox	   TEXT DEFAULT '.', /* RP mbox */
       rp_txt	   TEXT DEFAULT '.', /* RP txt */
       no_dhcp     BOOL DEFAULT false,  /* no-DHCP flag */
       range_start INET, /* auto assign address range start */
       range_end   INET, /* auto assign address range end */
       comment	   TEXT, /* comment */

       CONSTRAINT  nets_key UNIQUE (net,server)
) INHERITS(common_fields);


