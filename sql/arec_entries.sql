/* arec_entries table creation
 *
 * $Id$
 */

/** pointers to A record aliased hosts, linked to a host record. **/

CREATE TABLE arec_entries (
      id	   SERIAL PRIMARY KEY, /* unique ID */
      host	   INT4 NOT NULL, /* ptr to hosts table id
					-->hosts.id */
      arec         INT4 NOT NULL  /* ptr to aliased host id 
					-->hosts.id */
);

