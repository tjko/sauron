/* a_entries table creation
 *
 * addresses (A records) for hosts, linked to a host record.
 *
 * $Id$
 */

CREATE TABLE a_entries (
      id	   SERIAL PRIMARY KEY,
      host	   INT4 NOT NULL, /* ptr to hosts table id */

      ip	   INET,
      reverse	   BOOL DEFAULT true, /* generate reverse (PTR) record */
      forward      BOOL DEFAULT true, /* generate (A) record */
      comment	   CHAR(20)
);

