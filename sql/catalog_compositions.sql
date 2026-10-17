/* catalog_compositions table creation
 *
 * table to store composition of aggregate catalog zones (type 'A')
 * Each aggregate catalog zone is composed of one or more source
 * catalog zones (type 'C') with a priority for conflict resolution.
 *
 * Lower priority number = higher precedence when the same member zone
 * appears in multiple source catalogs.
 *
 * $Id:$
 */

/** This table stores the composition of aggregate catalog zones. **/

CREATE TABLE catalog_compositions (
       id                SERIAL PRIMARY KEY,    /* unique ID */
       composite_zone_id INT4 NOT NULL,         /* ptr to zones table (type='A')
                                                   -->zones.id */
       source_zone_id    INT4 NOT NULL,         /* ptr to zones table (type='C')
                                                   -->zones.id */
       priority          INT4 NOT NULL DEFAULT 100,
                                                /* lower number = higher priority
                                                   in conflict resolution */

       /* Constraints */
       CONSTRAINT catalog_compositions_composite_fk
           FOREIGN KEY (composite_zone_id) REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT catalog_compositions_source_fk
           FOREIGN KEY (source_zone_id) REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT catalog_compositions_unique
           UNIQUE (composite_zone_id, source_zone_id),
       CONSTRAINT catalog_compositions_priority
           CHECK (priority > 0),
       CONSTRAINT catalog_compositions_no_self
           CHECK (composite_zone_id != source_zone_id)
);

/* Indexes for fast lookups */
CREATE INDEX idx_catalog_compositions_composite
    ON catalog_compositions(composite_zone_id);
CREATE INDEX idx_catalog_compositions_priority
    ON catalog_compositions(composite_zone_id, priority);
