/* a_entries table creation
 *
 * $Id$
 */

/** Addresses (A records) for hosts, linked to a host record. **/

CREATE TABLE a_entries (
      id	   SERIAL PRIMARY KEY, /* unique ID */
      host	   INT4 NOT NULL, /* ptr to hosts table id
					-->hosts.id  */

      ip	   INET, /* IP number */
      reverse	   BOOL DEFAULT true, /* generate reverse (PTR) record flag */
      forward      BOOL DEFAULT true, /* generate (A) record flag */
      comment	   CHAR(20)
);

