/* wks_templates table creation
 *
 * WKS entry templates, hosts may link to one entry
 * in this table. Entries are server specific.
 *
 * $Id$
 */

CREATE TABLE wks_templates (
	id		SERIAL PRIMARY KEY,
	server		INT4 NOT NULL,
	name		TEXT,
	comment		TEXT

	/* wks */
);

