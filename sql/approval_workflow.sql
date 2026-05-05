/* DNS change approval workflow tables */

/* approval policy per zone */
CREATE TABLE approval_policies (
       id         SERIAL PRIMARY KEY,
       zone_id    INT4 NOT NULL,
       name       TEXT NOT NULL CHECK(name <> ''),
       active     BOOL DEFAULT true,
       on_add     BOOL DEFAULT false,
       on_modify  BOOL DEFAULT true,
       on_delete  BOOL DEFAULT false,
       match_mode CHAR(1) DEFAULT 'O' CHECK(match_mode ~ '^[OA]$'), /* O=OR, A=AND */
       comment    TEXT,

       CONSTRAINT approval_policies_zone_fk
           FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
) INHERITS(pokemon);

CREATE INDEX approval_policies_zone_index ON approval_policies(zone_id);


/* rules that trigger the policy */
CREATE TABLE approval_rules (
       id            SERIAL PRIMARY KEY,
       policy_id     INT4 NOT NULL,
       record_types  TEXT, /* comma separated Sauron type integers */
       domain_regexp TEXT, /* regexp for hosts.domain */
       comment       TEXT,

       CONSTRAINT approval_rules_policy_fk
           FOREIGN KEY (policy_id) REFERENCES approval_policies(id) ON DELETE CASCADE
) INHERITS(pokemon);

CREATE INDEX approval_rules_policy_index ON approval_rules(policy_id);


/* multi-step approval (cascade) */
CREATE TABLE approval_levels (
       id          SERIAL PRIMARY KEY,
       policy_id   INT4 NOT NULL,
       level_order INT4 NOT NULL DEFAULT 1,
       level_type  CHAR(1) DEFAULT 'O' CHECK(level_type ~ '^[OA]$'), /* O=OR, A=AND */
       name        TEXT NOT NULL CHECK(name <> ''),
       comment     TEXT,

       CONSTRAINT approval_levels_policy_fk
           FOREIGN KEY (policy_id) REFERENCES approval_policies(id) ON DELETE CASCADE,
       CONSTRAINT approval_levels_unique
           UNIQUE (policy_id, level_order)
) INHERITS(pokemon);

CREATE INDEX approval_levels_policy_index ON approval_levels(policy_id);


/* approvers for a given level */
CREATE TABLE approval_level_approvers (
       id       SERIAL PRIMARY KEY,
       level_id INT4 NOT NULL,
       user_id  INT4 NOT NULL,
       comment  TEXT,

       CONSTRAINT approval_level_approvers_level_fk
           FOREIGN KEY (level_id) REFERENCES approval_levels(id) ON DELETE CASCADE,
       CONSTRAINT approval_level_approvers_user_fk
           FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
       CONSTRAINT approval_level_approvers_unique
           UNIQUE (level_id, user_id)
) INHERITS(pokemon);

CREATE INDEX approval_level_approvers_level_index ON approval_level_approvers(level_id);
CREATE INDEX approval_level_approvers_user_index ON approval_level_approvers(user_id);


/* change request snapshot; applied only after approval */
CREATE TABLE dns_change_requests (
       id              SERIAL PRIMARY KEY,
       zone_id         INT4 NOT NULL,
       policy_id       INT4,
       requestor_id    INT4 NOT NULL,
       requestor_email TEXT,
       operation       CHAR(1) NOT NULL CHECK(operation ~ '^[AMD]$'), /* A=add, M=modify, D=delete */
       status          CHAR(1) DEFAULT 'P' CHECK(status ~ '^[PARC]$'), /* P/A/R/C */
       current_level   INT4 DEFAULT 1,
       host_id         INT4,
       change_data     TEXT NOT NULL,
       original_data   TEXT,
       reason          TEXT,
       comment         TEXT,

       CONSTRAINT dns_change_requests_zone_fk
           FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE,
       CONSTRAINT dns_change_requests_policy_fk
           FOREIGN KEY (policy_id) REFERENCES approval_policies(id),
       CONSTRAINT dns_change_requests_requestor_fk
           FOREIGN KEY (requestor_id) REFERENCES users(id) ON DELETE CASCADE
) INHERITS(pokemon);

CREATE INDEX dns_change_requests_zone_index ON dns_change_requests(zone_id);
CREATE INDEX dns_change_requests_status_index ON dns_change_requests(status);
CREATE INDEX dns_change_requests_requestor_index ON dns_change_requests(requestor_id);


/* approval decisions per approver */
CREATE TABLE dns_change_approvals (
       id            SERIAL PRIMARY KEY,
       request_id    INT4 NOT NULL,
       level_id      INT4 NOT NULL,
       user_id       INT4 NOT NULL,
       decision      CHAR(1) CHECK(decision ~ '^[AR]$'),
       reason        TEXT,
       decided_at    TIMESTAMP,
       email_sent    TIMESTAMP,

       CONSTRAINT dns_change_approvals_request_fk
           FOREIGN KEY (request_id) REFERENCES dns_change_requests(id) ON DELETE CASCADE,
       CONSTRAINT dns_change_approvals_level_fk
           FOREIGN KEY (level_id) REFERENCES approval_levels(id) ON DELETE CASCADE,
       CONSTRAINT dns_change_approvals_user_fk
           FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) INHERITS(pokemon);

CREATE INDEX dns_change_approvals_request_index ON dns_change_approvals(request_id);
CREATE INDEX dns_change_approvals_user_index ON dns_change_approvals(user_id);
CREATE INDEX dns_change_approvals_decision_index ON dns_change_approvals(decision);


/* audit log for approval workflow */
CREATE TABLE dns_change_audit_log (
       id         SERIAL PRIMARY KEY,
       request_id INT4 NOT NULL,
       user_id    INT4,
       user_name  TEXT,
       event      CHAR(1) NOT NULL CHECK(event ~ '^[SEARPXC]$'),
       level_order INT4,
       message    TEXT,
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

       CONSTRAINT dns_change_audit_log_request_fk
           FOREIGN KEY (request_id) REFERENCES dns_change_requests(id) ON DELETE CASCADE
);

CREATE INDEX dns_change_audit_log_request_index ON dns_change_audit_log(request_id);
CREATE INDEX dns_change_audit_log_event_index ON dns_change_audit_log(event);

ALTER TABLE approval_policies OWNER TO sauron;
ALTER TABLE approval_rules OWNER TO sauron;
ALTER TABLE approval_levels OWNER TO sauron;
ALTER TABLE approval_level_approvers OWNER TO sauron;
ALTER TABLE dns_change_requests OWNER TO sauron;
ALTER TABLE dns_change_approvals OWNER TO sauron;
ALTER TABLE dns_change_audit_log OWNER TO sauron;
