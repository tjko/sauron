/* full-privileges.sql  - code to grant user full privileges to the database
 *
 * $Id$
 */

GRANT ALL ON groups TO :user:;
GRANT ALL ON hosts TO :user:;
GRANT ALL ON nets TO :user:;
GRANT ALL ON pokemon TO :user:;
GRANT ALL ON printer_classes TO :user:;
GRANT ALL ON rr_a TO :user:;
GRANT ALL ON rr_mx TO :user:;
GRANT ALL ON rr_wks TO :user:;
GRANT ALL ON servers TO :user:;
GRANT ALL ON zones TO :user:;
GRANT ALL ON allow_transfer TO :user:;
GRANT ALL ON allow_update TO :user:;

GRANT ALL ON groups_id_seq TO :user:;
GRANT ALL ON hosts_id_seq TO :user:;
GRANT ALL ON nets_id_seq TO :user:;
// GRANT ALL ON pokemon_id_seq TO :user:;
GRANT ALL ON printer_classes_id_seq TO :user:;
GRANT ALL ON rr_a_id_seq TO :user:;
GRANT ALL ON rr_mx_id_seq TO :user:;
GRANT ALL ON rr_wks_id_seq TO :user:;
GRANT ALL ON servers_id_seq TO :user:;
GRANT ALL ON zones_id_seq TO :user:;
GRANT ALL ON allow_transfer_id_seq TO :user:;
GRANT ALL ON allow_update_id_seq TO :user:;

