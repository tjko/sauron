# Sauron Project Agents

Custom agents for Sauron database management system focusing on Perl module development, SQL schema patterns, and code formatting standards.

## ErrorCodeStandards
**Purpose:** Standardized error codes and exit code management for Sauron.

**Expertise:**
- Error code definitions and constants
- Exit codes (0-255) for shell integration
- Return codes (negative for errors) for function results
- Database-specific error codes
- Form validation error codes
- Best practices for error handling
- Migration from ad-hoc codes to standardized system
- Code review for consistency and uniqueness

**Style Guidelines:**
- Always use `Sauron::ErrorCodes` constants, never magic numbers
- Exit codes: use EXIT_* constants with meaningful names
- Return codes: use RET_* constants, 0/positive for success, negative for errors
- Database errors: clearly distinguish prepare (-1) vs execute (-2) failures
- Always check return values immediately after function calls
- Log all error conditions via `write2log()` with context
- Document error codes in function/script comments
- Use selective imports with `:exit`, `:return`, `:database`, `:form` tags

**When to Use:** Implementing error handling, code review, migrating legacy error codes, debuggingReturnCodeSystems.

---

## PerlModule
**Purpose:** Perl module development and maintenance for Sauron packages.

**Expertise:**
- Perl module structure (`package Sauron::*`, `@EXPORT`, `@ISA`)
- DBI database interface patterns
- Strict mode and syntax compliance
- Function documentation and comments
- Module naming conventions (camelCase mix with underscores)
- Error handling patterns (using syslog, error messages)

**Style Guidelines:**
- Use `use strict;` in all modules
- Export functions via `@EXPORT` array
- Document functions with comments describing parameters and return values
- Use `$_prefixed_names` for private variables
- Opening braces on same line: `sub function() {`
- Tab indentation for code blocks
- Comments align explanations for related variables

**When to Use:** Implementing or modifying Perl modules in `Sauron/` directory, fixing module imports, debugging function exports.

---

## SQLSchema
**Purpose:** SQL database schema design, queries, and table structure for Sauron.

**Expertise:**
- PostgreSQL dialect and syntax
- Table inheritance patterns (`INHERITS(pokemon)`)
- Primary key and constraint design
- Column typing (SERIAL, TEXT, BOOL, INT4, CIDR, TIMESTAMP)
- Audit columns (cdate, cuser, mdate, muser, expiration)
- Foreign key relationships
- Index optimization
- Migration scripts and conversions

**Style Guidelines:**
- Table names in lowercase singular form: `servers`, `zones`, `hosts`
- Column names in lowercase with underscores: `created_date`, `modified_user`
- Comments above column definitions explain purpose
- Constraints inline with column definition or after table creation
- DEFAULT values and CHECK constraints specified explicitly
- TIMESTAMP fields use `DEFAULT CURRENT_TIMESTAMP`
- Tab-align column definitions for readability
- Use /* */ comments for table documentation

**Example:**
```sql
CREATE TABLE servers ( 
       id         SERIAL PRIMARY KEY,
       name       TEXT UNIQUE NOT NULL CHECK(name <> ''),
       hostname   TEXT,        /* primary servername for SOA */
       comment    TEXT
) INHERITS(pokemon);
```

**When to Use:** Designing schema, creating views, writing conversion scripts, optimizing queries in `sql/` directory.

---

## CodeFormatter
**Purpose:** Enforce consistent code formatting across Perl and SQL files.

**Expertise:**
- Tab vs. space indentation rules
- Column alignment for readability
- Comment placement and style
- Line length guidelines
- Multiline function parameters
- Variable declaration formatting
- SQL statement indentation

**Style Guidelines:**
- Tab indentation (8 spaces per tab)
- Align columns in function signatures and SQL definitions
- Comments use `#` for Perl, `/* */` or `--` for SQL
- Max line width: ~80 characters where practical
- Function bodies consistently indented
- SQL keywords uppercase in queries: SELECT, FROM, WHERE, JOIN
- Perl keywords lowercase: sub, my, if, while, for, foreach

**When to Use:** Pre-commit code review, formatting existing files, checking style compliance.

---

## DBInterface
**Purpose:** Database connectivity and query patterns unique to Sauron.

**Expertise:**
- DBI connection management (`db_connect`, `db_connect2`)
- Connection string (DSN) handling
- Error handling via `$DBI::errstr`
- Query execution (`db_query`, `db_exec`)
- Transaction control (`db_begin`, `db_commit`, `db_rollback`)
- String encoding for internationalization
- Timestamp conversion functions
- Last insert ID retrieval (`db_lastid`)

**Style Guidelines:**
- Global connection handle: `$dbh`
- Error messages logged to syslog via `write2log()`
- SQL parameters passed as lists (not string interpolation)
- Connection credentials from environment/config: `$main::DB_DSN`, `$main::DB_USER`, `$main::DB_PASSWORD`
- Return 0 or 1 for success/failure
- Timestamp strings in format handled by `db_timestamp_str()`

**When to Use:** Debugging database connections, implementing new query functions, fixing transaction issues.

---

## ConfigManagement
**Purpose:** Configuration file management and CGI-based configuration editing.

**Expertise:**
- Configuration file parsing
- CGI parameter handling in `cgi/` scripts
- Form-based configuration editing
- Plugin configuration (`.conf` files)
- Database-backed settings storage

**When to Use:** Modifying configuration files, debugging CGI forms, adding new configuration options.

---

## TestSuite
**Purpose:** Test implementation and validation for new features.

**Expertise:**
- Test file organization in `test/` directory
- Perl testing frameworks
- SQL test data setup and teardown
- Validation of imports and conversions
- CI workflow integration for new tests (`.github/workflows/ci.yml`)

**Style Guidelines:**
- When adding a new test file (`t/*.t`), always include it in CI workflow execution.
- Keep unit tests in fast CI stages and integration/E2E tests in DB-enabled CI stages.

**When to Use:** Creating unit tests, testing database conversions, validating import scripts.

---

## DatabaseDiagnostics
**Purpose:** Access Sauron PostgreSQL database from shell scripts and diagnostics.

**Expertise:**
- PostgreSQL command-line client (`psql`) usage
- Disabling pager output for scriptable results
- Database connection management for diagnostic queries
- Avoiding terminal buffer/pager issues during automation
- Redirecting SQL output to files for processing

**Connection Method:**
For all database access from shell scripts, use:
```bash
sudo -u postgres -- psql sauron -P pager=off -c 'SELECT ...;'
```

Key flags:
- `sudo -u postgres` - Run as postgres system user (required for peer authentication)
- `--` - Separator before psql command (recommended)
- `-P pager=off` - Disable pager mode (essential for scripts)
- `-c '...'` - Execute command and exit
- Output redirection: `> /tmp/output.txt 2>&1` - Capture to file if needed

**Common Patterns:**
```bash
# Simple query with output to stdout
sudo -u postgres -- psql sauron -P pager=off -c "SELECT * FROM hosts WHERE domain='test19';"

# Query with file output (for large results or processing)
sudo -u postgres -- psql sauron -P pager=off -c "SELECT ..." > /tmp/result.txt 2>&1

# Pipe output to head/tail for filtering
sudo -u postgres -- psql sauron -P pager=off -c "SELECT ..." | head -20
```

**Troubleshooting:**
- If output goes into pager mode: Add `-P pager=off` flag
- If psql hangs: The `-c` flag should exit immediately after query
- If authentication fails: Verify running as postgres user with `sudo -u postgres`
- Large result sets: Always redirect to file or use LIMIT in query

**When to Use:** Database diagnostics, approval workflow debugging, schema verification, query testing during development.
