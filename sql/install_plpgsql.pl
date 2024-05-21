#!/usr/bin/perl

# Add PL/pgsql language to Sauron database.
# University of Jyväskylä / Teppo Vuori 21.09.2017
# $Id:$

use strict;
use warnings;
my ($sql, $res);

# Copied from http://timmurphy.org/2011/08/27/create-language-if-it-doesnt-exist-in-postgresql/
$sql = <<'END_SQL';
CREATE OR REPLACE FUNCTION create_language_plpgsql()
RETURNS BOOLEAN AS \$\$
    CREATE LANGUAGE plpgsql;
    SELECT TRUE;
\$\$ LANGUAGE SQL;

SELECT CASE WHEN NOT
    (
        SELECT  TRUE AS exists
        FROM    pg_language
        WHERE   lanname = 'plpgsql'
        UNION
        SELECT  FALSE AS exists
        ORDER BY exists DESC
        LIMIT 1
    )
THEN
    create_language_plpgsql()
ELSE
    FALSE
END AS plpgsql_created;

DROP FUNCTION create_language_plpgsql();
END_SQL
# End of copied section.

# Get PostgreSQL version.
$res = `psql -U postgres sauron -c 'select version();' | grep PostgreSQL`;
if ($res !~ /PostgreSQL\s*\d+\.\d+/) { die("Cannot get PostgrSQL version\n$res\n") };
chomp $res;
$res =~ s/^\D*(\d+\.\d+).*$/$1/;

# ** $res = '9.1';

# Create PL/pgsql.
if ($res =~ /^(8\.\d|9\.0)$/) { # <= 9.0

# In PostgreSQL 9.0 we could simply say "create or replace language ..." but in 8.x we can only say
# "create language ..." which causes an error if the language already exists, and for this reason
# we need a fairly long workaround (above).
    $res = `psql -U postgres sauron -c "$sql"`;
    if ($res !~ /DROP FUNCTION/i) {
	die ("Failed to create PL/pgsql in Sauron database (1)\n$res\n");
    }

} else { # >= 9.1

# Starting with PostgreSQL 9.1 we can use "create extension ..." and later that becomes the only
# way to add PL/pgsql to the database.
    $res = `psql -U postgres sauron -c 'create extension if not exists plpgsql with schema pg_catalog;'`;
    if ($res !~ /CREATE EXTENSION/i) {
	die ("Failed to create PL/pgsql in Sauron database (2)\n$res\n");
    }

}

exit(0);

# eof
