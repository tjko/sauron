/* printer_classes table creation
 *
 * global table to store printer classes (printcap stuff)
 * these classess maybe referred to in PRINTER fields in other tables. 
 *
 * $Id$
 */

CREATE TABLE printer_classes (
       id           SERIAL PRIMARY KEY,
       name	    TEXT UNIQUE NOT NULL CHECK(name <> ''),

       comment	    TEXT

       /* printer (printer_entries) */
       /* dentries */

) INHERITS(pokemon);

