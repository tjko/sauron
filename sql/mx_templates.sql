/* mx_templates table creation
 *
 * MX entry templates, hosts may link to one entry in this table.
 * Entries are zone specific.
 *
 * $Id$
 */

CREATE TABLE mx_templates (
	id		SERIAL PRIMARY KEY,
	zone		INT4 NOT NULL,
	name		TEXT,
	comment		TEXT

       /* mx */
);


