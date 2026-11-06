/* zone_catalog_groups table creation
 *
 * table to store group assignments for catalog zone members
 * A member zone can belong to multiple groups within a catalog (RFC 9432 §5.2)
 *
 * Groups allow secondary servers to apply different configurations
 * to different sets of member zones (e.g., different DNSSEC policies,
 * also-notify lists, etc.)
 *
 * $Id:$
 */

/** This table stores group assignments for catalog zone memberships. **/

CREATE TABLE zone_catalog_groups (
       id              SERIAL PRIMARY KEY,    /* unique ID */
       zone_catalog_id INT4 NOT NULL,         /* ptr to zone_catalogs table
                                                -->zone_catalogs.id */
       group_name      TEXT NOT NULL CHECK(group_name <> ''),
                                              /* RFC 9432 group property name */

       /* Constraints */
       CONSTRAINT zone_catalog_groups_fk FOREIGN KEY (zone_catalog_id)
           REFERENCES zone_catalogs(id) ON DELETE CASCADE,
       CONSTRAINT zone_catalog_groups_unique
           UNIQUE (zone_catalog_id, group_name)
);

/* Indexes for fast lookups */
CREATE INDEX idx_zone_catalog_groups_ref ON zone_catalog_groups(zone_catalog_id);
CREATE INDEX idx_zone_catalog_groups_name ON zone_catalog_groups(group_name);

