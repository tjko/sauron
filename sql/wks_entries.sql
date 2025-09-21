/* wks_entries table creation
 *
 * $Id:$
 */

/** This table contains WKS record entries. **/

CREATE TABLE wks_entries (
	id	    SERIAL PRIMARY KEY, /* unique ID */
	type        INT4 NOT NULL, /* type:
					1=host,
					2=wks_template */
        ref         INT4 NOT NULL, /* ptr to table speciefied by type field 
					-->hosts.id
					-->wks_templates.id */
	proto	    CHAR(10), /* protocol (tcp,udp) */
	services    TEXT, /* services (ftp,telnet,smtp,http,...) */
        comment     TEXT
) WITH OIDS;

CREATE INDEX wks_entries_ref_index ON wks_entries (type,ref);

