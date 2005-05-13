/* leases table creation
 *
 * $Id$
 */

/** Stores information about DHCP server leases  **/

CREATE TABLE leases (
      id	   SERIAL PRIMARY KEY, /* unique ID */
      server	   INT4 NOT NULL, /* ptr to servers table id
					-->servers.id  */
      host	   INT4 NOT NULL, /* optional ptr to hosts table id
					-->hosts.id */
      ip	   INET, /* IP number */
      ipv6	   TEXT, /* reserved */
      lstart	   INT4, /* lease start time */
      lend         INT4, /* lease end time */
      mac          CHAR(12), /* Ethernet address */
      state	   INT4 DEFAULT 0, /* lease state */
      uid	   TEXT, /* dhcp uid */
      hostname     TEXT, /* dhcp hostname */
      info	   TEXT  /* extra info */
);

CREATE INDEX leases_mac_index ON leases (mac);
CREATE INDEX leases_ip_index ON leases (ip);
CREATE INDEX leases_host_index ON leases (host);

