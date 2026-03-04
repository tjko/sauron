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
    flags       CHAR(1) NOT NULL CHECK (flags ~* '^[AUSP]$'), /* value:
                        A=A or AAAA record
                        S=SRV record
                        U=URI
                        P=Protocol specific */
    service       TEXT NOT NULL, /* service name, example: "E2U+sip" */
    regexp        TEXT NOT NULL, /* regexp by RFC 2915 */
    replacement   TEXT NOT NULL, /* target FQDN (can be ".") */
    comment     TEXT /* comment */
);

CREATE INDEX naptr_entries_ref_index ON naptr_entries (type,ref);
CREATE INDEX naptr_entries_order_pref_index ON naptr_entries (order_val, preference);
