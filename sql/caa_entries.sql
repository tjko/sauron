/* caa_entries table creation
 *
 */

/** This table contains CAA record entries. **/

CREATE TABLE caa_entries (
    id          SERIAL PRIMARY KEY, /* unique ID */
    type        INT4 NOT NULL, /* type:
                        1=host */
    ref         INT4 NOT NULL, /* ptr to table specefied by type field
                        -->hosts.id */
    flags       INT4 NOT NULL CHECK (flags >= 0 AND flags <= 255), /* RFC 8659: flags */
    tag         TEXT NOT NULL CHECK (tag ~ '^[A-Za-z0-9]+$'), /* property tag */
    value       TEXT NOT NULL, /* property value without surrounding quotes */
    comment     TEXT /* comment */
);

CREATE INDEX caa_entries_ref_index ON caa_entries (type,ref);
CREATE INDEX caa_entries_flags_tag_index ON caa_entries (flags,tag);