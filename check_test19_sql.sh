#!/bin/bash

# Check test19 approval workflow using psql without pager

echo "=== TEST19 APPROVAL WORKFLOW CHECK ===" | tee /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt

# Check 1: Find host test19
echo "Check 1: Finding host test19 in zone acad.cz (zone_id=5)" | tee -a /tmp/test19_check.txt
psql -P pager=off -d sauron -c "SELECT id, domain, type FROM hosts WHERE domain = 'test19' AND zone = 5;" | tee -a /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt

# Check 2: List all approval policies for acad.cz
echo "Check 2: Finding approval policies for acad.cz (zone_id=5)" | tee -a /tmp/test19_check.txt
psql -P pager=off -d sauron -c "SELECT id, name, active, on_add, on_modify, on_delete, match_mode FROM approval_policies WHERE zone_id = 5;" | tee -a /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt

# Check 3: List all approval rules for policies in acad.cz
echo "Check 3: Finding approval rules for those policies" | tee -a /tmp/test19_check.txt
psql -P pager=off -d sauron -c "SELECT ap.id as policy_id, ar.id as rule_id, ar.record_types, ar.domain_regexp FROM approval_policies ap JOIN approval_rules ar ON ap.id = ar.policy_id WHERE ap.zone_id = 5 ORDER BY ap.id, ar.id;" | tee -a /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt

# Check 4: Look for change requests
echo "Check 4: Looking for approval requests for test19" | tee -a /tmp/test19_check.txt
psql -P pager=off -d sauron -c "SELECT dcr.id, dcr.operation, dcr.status, h.domain FROM dns_change_requests dcr JOIN hosts h ON dcr.host_id = h.id WHERE dcr.zone_id = 5 AND h.domain = 'test19';" | tee -a /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt

echo "=== END ===" | tee -a /tmp/test19_check.txt
echo "" | tee -a /tmp/test19_check.txt
echo "Full output saved to /tmp/test19_check.txt"
