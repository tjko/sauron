/* printer_entries table creation
 *
 * $Id:$
 */

/** This table contains printer definition entries. **/

CREATE TABLE printer_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=group,
					2=host,
					3=printer_class */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field 
					-->groups.id
					-->hosts.id
					-->printer_classes.id */
	printer	    TEXT, /* printcap entry */
        comment     TEXT
);


