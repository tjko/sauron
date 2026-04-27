#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use Sauron::DB;
use Sauron::Approval;

# Initialize database connection
my $dbh = db_connect();
die "Cannot connect to database!" unless $dbh;

print "=== APPROVAL WORKFLOW DEBUG ===\n\n";

# 1. Check if zone acad.cz exists
print "1. Looking for zone acad.cz...\n";
my @zones;
db_query("SELECT id, name FROM zones WHERE name = 'acad.cz'", \@zones);
if (@zones) {
    print "   Zone found: ID=" . $zones[0][0] . "\n";
    my $zone_id = $zones[0][0];
    
    # 2. Check approval policies for this zone
    print "\n2. Checking approval policies for zone ID=$zone_id...\n";
    my @policies;
    db_query("SELECT id, name, active, on_add, on_modify, on_delete, match_mode " .
             "FROM approval_policies WHERE zone_id = $zone_id", \@policies);
    
    if (@policies) {
        print "   Found " . scalar(@policies) . " policy(ies):\n";
        foreach my $p (@policies) {
            my ($pid, $pname, $active, $on_add, $on_mod, $on_del, $match_mode) = @$p;
            print "   - Policy ID=$pid, name='$pname', active=$active\n";
            print "     on_add=$on_add, on_modify=$on_mod, on_delete=$on_del, match_mode=$match_mode\n";
            
            # Check rules for this policy
            my @rules;
            db_query("SELECT id, record_types, domain_regexp FROM approval_rules " .
                     "WHERE policy_id = $pid", \@rules);
            if (@rules) {
                print "     Rules:\n";
                foreach my $r (@rules) {
                    print "       - types='" . ($r->[1] // '') . "', regexp='" . ($r->[2] // '') . "'\n";
                }
            } else {
                print "     Rules: NONE (policy applies to all)\n";
            }
        }
    } else {
        print "   NO POLICIES FOUND for this zone!\n";
    }
    
    # 3. Check host test18
    print "\n3. Looking for host test18 in zone acad.cz...\n";
    my @hosts;
    db_query("SELECT id, domain, type, zone FROM hosts " .
             "WHERE domain = 'test18' AND zone = $zone_id", \@hosts);
    
    if (@hosts) {
        print "   Host found: ID=" . $hosts[0][0] . ", type=" . $hosts[0][2] . "\n";
        my $host_id = $hosts[0][0];
        my $host_type = $hosts[0][2];
        
        # 4. Test check_approval_needed for Add operation
        print "\n4. Testing check_approval_needed for Add operation...\n";
        my $policy_id = check_approval_needed($zone_id, 'A', $host_type, 'test18');
        if (defined $policy_id) {
            print "   APPROVAL NEEDED: policy_id=$policy_id\n";
        } else {
            print "   APPROVAL NOT NEEDED (policy_id is undef)\n";
        }
        
        # 5. Check dns_change_requests for this host
        print "\n5. Looking for dns_change_requests for host ID=$host_id...\n";
        my @requests;
        db_query("SELECT id, status, operation FROM dns_change_requests " .
                 "WHERE host_id = $host_id ORDER BY id DESC", \@requests);
        
        if (@requests) {
            print "   Found " . scalar(@requests) . " request(s):\n";
            foreach my $r (@requests) {
                print "   - Request ID=" . $r->[0] . ", operation=" . $r->[2] . ", status=" . $r->[1] . "\n";
            }
        } else {
            print "   NO REQUESTS FOUND for this host\n";
        }
        
    } else {
        print "   HOST NOT FOUND\n";
    }
    
} else {
    print "   Zone NOT FOUND\n";
}

db_disconnect();
print "\n=== END DEBUG ===\n";
