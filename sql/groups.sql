/* groups table creation
 *
 *
 * $Id$
 */

/** Group descriptions, linked to server record. Hosts can "belong" to
    one group and get DHCP/printer/etc definitions from that group. **/

CREATE TABLE groups (
       id	    SERIAL PRIMARY KEY, /* unique ID */
       server	    INT4 NOT NULL, /* ptr to a servers table record
					-->servers.id */

       name	    TEXT NOT NULL CHECK(name <> ''), /* group name */
       comment	    TEXT,

       CONSTRAINT   groups_key UNIQUE(name,server)
) INHERITS(pokemon);

