/*
 * naptr_entries table creation
 */

/** This table contains NAPTR record entries. **/

CREATE TABLE naptr_entries (
    id          SERIAL PRIMARY KEY, /* unique ID */
    type        INT4 NOT NULL, /* type:
                       1=host */
    ref         INT4 NOT NULL, /* ptr to table specefied by type field
                        -->hosts.id */
    order_val   INT4 NOT NULL CHECK (order_val >= 0), /* RFC 2915: ORDER */
    preference  INT4 NOT NULL CHECK (preference >= 0), /* RFC 2915: PREFERENCE */
    flags       CHAR(1) CHECK (flags ~ '^[AUSP]?$'), /* RFC 2915: FLAGS
                        empty=non-terminal, A=A/AAAA, S=SRV, U=URI, P=PTR */
    service     TEXT, /* RFC 2915: service name, can be empty if regexp is defined */
    regexp      TEXT, /* RFC 2915: regexp - can be empty */
    replacement TEXT NOT NULL, /* target FQDN (can be ".") */
    comment     TEXT /* comment */
);

CREATE INDEX naptr_entries_ref_index ON naptr_entries (type,ref);
CREATE INDEX naptr_entries_order_pref_index ON naptr_entries (order_val, preference);
