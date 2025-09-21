/* user_groups table creation
 *
 * $Id:$
 */

/** This table contains records defining user groups.  **/

CREATE TABLE user_groups (
       id           SERIAL PRIMARY KEY,                /* unique ID */
       name	    TEXT NOT NULL CHECK (name <> ''),  /* group name */     
       comment	    TEXT,                              /* comments */

       CONSTRAINT   user_groups_name_key UNIQUE(name)
) WITH OIDS;


