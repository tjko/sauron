/* mx_templates table creation
 *
 * $Id$
 */

/** MX entry templates, hosts may link to one entry in this table.
    Entries are zone specific. **/

CREATE TABLE mx_templates (
	id		SERIAL PRIMARY KEY, /* unique ID */
	zone		INT4 NOT NULL, /* ptr to a zone table record
					  -->zones.id */
	name		TEXT, /* template name */
	comment		TEXT 
) INHERITS(common_fields);

