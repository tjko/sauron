/* vmps table creation
 *
 * $Id$
 */

/** VMPS domain definitions, linked to a server record. 
    Used for generating (Cisco) VMPS configuration files. **/

CREATE TABLE vmps (
       id	   SERIAL PRIMARY KEY, /* unique ID */
       server	   INT4 NOT NULL, /* ptr to a servers table record
					-->servers.id */

       name	   TEXT NOT NULL CHECK(name <> ''), /* name of VMPS domain */
       description TEXT, /* long name */
       mode        INT DEFAULT 0, /* mode: 0=open, 
	                                   1=secure */
       nodomainreq INT DEFAULT 0, /* no-domain-req: 0=allow, 
                                                    1=deny */
       fallback    INT DEFAULT -1, /* ptr to a vlans table record
                             	        -->vlans.id */
       comment	   TEXT, /* comments */

       CONSTRAINT  vmps_key UNIQUE (name,server)
) INHERITS(common_fields);


