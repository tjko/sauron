/* a_entries table creation
 *
 * $Id$
 */

/** Addresses (A records) for hosts, linked to a host record. **/

CREATE TABLE a_entries (
      id	   SERIAL PRIMARY KEY, /* unique ID */
      type         INT4 NOT NULL, /* type:
					1=zone,
					2=host */
      ref	   INT4 NOT NULL, /* ptr to table specified by type field
					-->zones.id
					-->hosts.id */

      ip	   INET, /* IP number */
      reverse	   BOOL DEFAULT true, /* generate reverse (PTR) record flag */
      forward      BOOL DEFAULT true, /* generate (A) record flag */
      comment	   CHAR(20)
);

