/* drop_tables.sql
 *
 * $Id$
 */

DROP TABLE a_entries;
DROP TABLE mx_templates;
DROP TABLE wks_templates;
DROP TABLE hosts;
DROP TABLE zones;
DROP TABLE servers;
DROP TABLE nets;
DROP TABLE groups;
DROP TABLE printer_classes;
DROP TABLE cidr_entries;
DROP TABLE dhcp_entries;
DROP TABLE printer_entries;
DROP TABLE ns_entries;
DROP TABLE mx_entries;
DROP TABLE txt_entries;
DROP TABLE wks_entries;
DROP TABLE srv_entries;
DROP TABLE arec_entries;
/* DROP TABLE host_info; */
DROP TABLE utmp;
DROP TABLE users;
DROP TABLE user_rights;
DROP TABLE user_groups;
DROP TABLE ether_info;
DROP TABLE settings;
DROP TABLE hinfo_templates;
DROP TABLE root_servers;
DROP TABLE lastlog;
DROP TABLE history;
DROP TABLE deleted_hosts;
DROP TABLE news;
DROP TABLE vlans;

DROP TABLE common_fields;

DROP SEQUENCE a_entries_id_seq;
DROP SEQUENCE mx_templates_id_seq;
DROP SEQUENCE wks_templates_id_seq;
DROP SEQUENCE hosts_id_seq;
DROP SEQUENCE zones_id_seq;
DROP SEQUENCE servers_id_seq;
DROP SEQUENCE nets_id_seq;
DROP SEQUENCE groups_id_seq;
DROP SEQUENCE printer_classes_id_seq;
DROP SEQUENCE cidr_entries_id_seq;
DROP SEQUENCE dhcp_entries_id_seq;
DROP SEQUENCE printer_entries_id_seq;
DROP SEQUENCE ns_entries_id_seq;
DROP SEQUENCE mx_entries_id_seq;
DROP SEQUENCE txt_entries_id_seq;
DROP SEQUENCE wks_entries_id_seq;
DROP SEQUENCE srv_entries_id_seq;
DROP SEQUENCE arec_entries_id_seq;
/* DROP SEQUENCE host_info_id_seq; */
DROP SEQUENCE users_id_seq;
DROP SEQUENCE user_rights_id_seq;
DROP SEQUENCE user_groups_id_seq;
DROP SEQUENCE hinfo_templates_id_seq;
DROP SEQUENCE root_servers_id_seq;
DROP SEQUENCE history_id_seq;
DROP SEQUENCE lastlog_id_seq;
DROP SEQUENCE news_id_seq;
DROP SEQUENCE vlans_id_seq;


DROP SEQUENCE sid_seq;

/* eof */
