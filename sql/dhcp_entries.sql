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
					4=net (IPv4 and IPv6 nets),
					5=group,
					6=vlan (shared-network),
					7=server local entries,
					11=server (IPv6 entry),
					13=host (IPv6 entry),
					15=group (IPv6 entry),
					16=vlan (IPv6 entry),
					17=server local (IPv6 entry) */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field
					-->servers.id
					-->zones.id
					-->hosts.id
					-->nets.id
					-->groups.id */
	dhcp	    TEXT, /* DHCP entry value (without trailing ';') */
        comment     TEXT,
	fmt	    INT4 DEFAULT 0 /* target configuration format:
					0=ISC and KEA (ISC syntax),
					1=ISC only (ISC syntax),
					2=KEA only (JSON, see Sauron::DhcpDefs) */
);

CREATE INDEX dhcp_entries_ref_index ON dhcp_entries (type,ref);

