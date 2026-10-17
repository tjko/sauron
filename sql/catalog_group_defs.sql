/* catalog_group_defs table creation
 *
 * table to store predefined group definitions for catalog zones
 * Allows administrators to define available groups per catalog zone
 * that can then be selected when assigning member zones.
 *
 * $Id:$
 */

/** This table stores predefined group definitions for catalog zones. **/

CREATE TABLE catalog_group_defs (
       id              SERIAL PRIMARY KEY,    /* unique ID */
       catalog_zone_id INT4 NOT NULL,         /* ptr to zones table - the catalog
                                                -->zones.id */
       group_name      TEXT NOT NULL CHECK(group_name <> ''),
                                              /* group name */
       comment         TEXT,                  /* description of the group */

       /* Constraints */
       CONSTRAINT catalog_group_defs_fk FOREIGN KEY (catalog_zone_id)
           REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT catalog_group_defs_unique
           UNIQUE (catalog_zone_id, group_name)
);

/* Indexes for fast lookups */
CREATE INDEX idx_catalog_group_defs_catalog ON catalog_group_defs(catalog_zone_id);

