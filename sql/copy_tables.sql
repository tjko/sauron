/* copy_tables.sql
 *
 * $Id$
 */


/* make copy of hosts table; for deleted records */

SELECT * INTO TABLE deleted_hosts FROM hosts WHERE id < 0;

/* eof */
