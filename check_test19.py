#!/usr/bin/env python3

import subprocess
import json
import sys

def run_sql(sql):
    """Run SQL command and return results"""
    cmd = ['sudo', '-u', 'postgres', 'psql', '-d', 'sauron', '-c', sql]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error: {e}"

# Check 1: Host test19
print("=" * 60)
print("CHECKING HOST test19")
print("=" * 60)
sql = "SELECT id, domain, type FROM hosts WHERE domain = 'test19' AND zone = 5;"
print("SQL:", sql)
print(run_sql(sql))

# Check 2: Approval policies for acad.cz
print("\n" + "=" * 60)
print("CHECKING APPROVAL POLICIES FOR acad.cz (zone_id=5)")
print("=" * 60)
sql = "SELECT id, name, active, on_add, on_modify, match_mode FROM approval_policies WHERE zone_id = 5;"
print("SQL:", sql)
print(run_sql(sql))

# Check 3: Approval rules
print("\n" + "=" * 60)
print("CHECKING APPROVAL RULES")
print("=" * 60)
sql = "SELECT ap.id as policy_id, ar.id as rule_id, ar.record_types, ar.domain_regexp FROM approval_policies ap LEFT JOIN approval_rules ar ON ap.id = ar.policy_id WHERE ap.zone_id = 5;"
print("SQL:", sql)
print(run_sql(sql))

# Check 4: DNS change requests for test19
print("\n" + "=" * 60)
print("CHECKING DNS CHANGE REQUESTS FOR test19")
print("=" * 60)
sql = """
SELECT dcr.id, dcr.operation, dcr.status, dcr.host_id 
FROM dns_change_requests dcr 
JOIN hosts h ON dcr.host_id = h.id 
WHERE h.domain = 'test19' AND h.zone = 5;
"""
print("SQL:", sql)
print(run_sql(sql))

# Check 5: Host type 1 aliases in check_approval_needed
print("\n" + "=" * 60)
print("ANALYSIS: Host type 1 aliases")
print("=" * 60)
print("""
In Sauron::Approval module, host type 1 (Host) has these aliases:
  1 => ['HOST','A','AAAA']

This means when checking approval_needed() with:
  - operation='A' (Add)
  - host_type=1 (Host/A/AAAA)
  - domain='test19'

The function checks if approval_rules.record_types contains:
  - '1' (exact type match)
  - 'HOST', 'A', or 'AAAA' (alias match)
  - Empty/NULL (match any type)

If none of the above, the rule type filter will FAIL.
""")
