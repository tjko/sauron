/* zone_catalogs table creation
 *
 * table to store many-to-many relationship between catalog zones
 * and their member zones
 *
 * Catalog zones are special zone types that aggregate metadata
 * about multiple zones and allow their configuration to be 
 * distributed via zone transfers in BIND 9.11+
 *
 * $Id:$
 */

/** This table contains the membership of zones within catalog zones. **/

CREATE TABLE zone_catalogs (
       id              SERIAL PRIMARY KEY, /* unique ID */
       catalog_zone_id INT4 NOT NULL, /* ptr to zones table - the catalog
                                        -->zones.id */
       member_zone_id  INT4 NOT NULL, /* ptr to zones table - member zone
                                        -->zones.id */

       version         CHAR(1) DEFAULT '2',  /* catalog zone version
                                               (BIND uses '2') */

       /* Constraints */
       CONSTRAINT zone_catalogs_catalog_fk FOREIGN KEY (catalog_zone_id)
           REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT zone_catalogs_member_fk FOREIGN KEY (member_zone_id)
           REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT zone_catalogs_unique UNIQUE (catalog_zone_id, member_zone_id),
       CONSTRAINT zone_catalogs_no_self CHECK (catalog_zone_id != member_zone_id)
);

/* Indexes for fast lookups */
CREATE INDEX idx_zone_catalogs_catalog ON zone_catalogs(catalog_zone_id);
CREATE INDEX idx_zone_catalogs_member ON zone_catalogs(member_zone_id);

