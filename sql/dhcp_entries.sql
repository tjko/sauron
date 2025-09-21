/* dhcp_entries table creation
 *
 * $Id:$
 */

/** This table contains DHCP options user in various contexts. **/

CREATE TABLE dhcp_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=server,
					2=zone,
					3=host,
					4=net,
					5=group
					6=vlan (shared-network) */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field
					-->servers.id
					-->zones.id
					-->hosts.id
					-->nets.id
					-->groups.id */
	dhcp	    TEXT, /* DHCP entry value (without trailing ';') */
        comment     TEXT
);

CREATE INDEX dhcp_entries_ref_index ON dhcp_entries (type,ref);

