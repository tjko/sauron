/* group_entries table creation
 *
 * $Id$
 */

/** subgroup memberships, pointers to group records, 
    linked to a host record. **/

CREATE TABLE group_entries (
      id	   SERIAL PRIMARY KEY, /* unique ID */
      host	   INT4 NOT NULL, /* ptr to hosts table id
					-->hostss.id */
      grp          INT4 NOT NULL  /* ptr to group (this host) belogs to
					-->groups.id */
);

