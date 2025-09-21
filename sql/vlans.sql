/* vlans table creation
 *
 * $Id:$
 */

/** "VLAN" (Layer-2 networks/shared networks) descriptions, 
    linked to server record. 
    Used mainly for generating of shared-network map for DHCP. **/

CREATE TABLE vlans (
       id	   SERIAL PRIMARY KEY, /* unique ID */
       server	   INT4 NOT NULL, /* ptr to a servers table record
					-->servers.id */

       name	   TEXT NOT NULL CHECK(name <> ''), /* name of vlan */
       vlanno	   INT,   /* vlan number (ID) */
       description TEXT,  /* long name */
       comment	   TEXT,  /* comments */

       CONSTRAINT  vlans_key UNIQUE (name,server)
) INHERITS(common_fields);


