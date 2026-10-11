/* drop_tables.sql
 *
 * $Id:$
 */

/* tables referencing other tables first, inheritance parents last;
   SERIAL sequences are dropped together with their tables */
DROP TABLE dns_change_audit_log;
DROP TABLE dns_change_approvals;
DROP TABLE dns_change_requests;
DROP TABLE approval_level_approvers;
DROP TABLE approval_levels;
DROP TABLE approval_rules;
DROP TABLE approval_policies;
DROP TABLE catalog_compositions;
DROP TABLE catalog_group_defs;
DROP TABLE zone_catalog_groups;
DROP TABLE zone_catalogs;

DROP TABLE a_entries;
DROP TABLE acls;
DROP TABLE arec_entries;
DROP TABLE caa_entries;
DROP TABLE cidr_entries;
DROP TABLE deleted_hosts;
DROP TABLE dhcp_entries;
DROP TABLE ds_entries;
DROP TABLE ether_info;
DROP TABLE group_entries;
DROP TABLE groups;
DROP TABLE hinfo_templates;
DROP TABLE history;
DROP TABLE hosts;
DROP TABLE keys;
DROP TABLE lastlog;
DROP TABLE leases;
DROP TABLE mx_entries;
DROP TABLE mx_templates;
DROP TABLE nets;
DROP TABLE news;
DROP TABLE ns_entries;
DROP TABLE printer_classes;
DROP TABLE printer_entries;
DROP TABLE root_servers;
DROP TABLE servers;
DROP TABLE settings;
DROP TABLE srv_entries;
DROP TABLE sshfp_entries;
DROP TABLE tlsa_entries;
DROP TABLE naptr_entries;
DROP TABLE txt_entries;
DROP TABLE user_groups;
DROP TABLE user_rights;
DROP TABLE users;
DROP TABLE utmp;
DROP TABLE vlans;
DROP TABLE vmps;
DROP TABLE wks_entries;
DROP TABLE wks_templates;
DROP TABLE zones;

DROP TABLE common_fields;
DROP TABLE pokemon;

DROP SEQUENCE sid_seq;

/* eof */
