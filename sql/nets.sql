/* nets table creation
 *
 * $Id$
 */

/** Net/subnet descriptions, linked to server record. 
    Used mainly for generating subnet map for DHCP and access 
    control/user friendliness in front-ends.  **/

CREATE TABLE nets (
       id	   SERIAL, /* unique ID */
       server	   INT4 NOT NULL, /* ptr to a servers table record
					-->servers.id */

       name	   TEXT, /* name of net/subnet */
       net	   CIDR NOT NULL, /* net CIDR */
       subnet      BOOL DEFAULT true, /* subnet flag */
       vlan	   CHAR(15) DEFAULT 'default', /* VLAN */

       rp_mbox	   TEXT DEFAULT '.', /* RP mbox */
       rp_txt	   TEXT DEFAULT '.', /* RP txt */
       no_dhcp     BOOL DEFAULT false,  /* no-DHCP flag */
       range_start INET, /* auto assign address range start */
       range_end   INET, /* auto assign address range end */
       comment	   TEXT, /* comment */

       CONSTRAINT  nets_key PRIMARY KEY (net,server)
) INHERITS(common_fields);


