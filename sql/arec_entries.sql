/* arec_entries table creation
 *
 * pointers to A record aliased hosts, linked to a host record.
 *
 * $Id$
 */

CREATE TABLE arec_entries (
      id	   SERIAL PRIMARY KEY,
      host	   INT4 NOT NULL, /* ptr to hosts table id */
      arec         INT4 NOT NULL  /* ptr to aliased host id */
);

