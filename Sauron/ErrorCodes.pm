# Sauron::ErrorCodes -- Standardized error codes and constants
#
# Central repository for all exit and return codes used throughout Sauron.
# This module ensures consistency and uniqueness of error codes across the system.
#
# Copyright (c) 2026 Sauron project
# $Id:$
#

package Sauron::ErrorCodes;
require Exporter;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION = '1.0';

@ISA = qw(Exporter);

# Export codes by default
@EXPORT = qw(
	EXIT_OK
	EXIT_GENERIC_ERROR
	EXIT_USAGE_ERROR
	EXIT_CONFIG_ERROR
	EXIT_PENDING_FOUND
	EXIT_DB_CONNECTION_FAILED
	EXIT_FILE_NOT_FOUND
	EXIT_FILE_PERMISSION_ERROR
	EXIT_LOCK_FAILED
	EXIT_SIGNAL_CAUGHT

	RET_OK
	RET_GENERIC_ERROR
	RET_NOT_FOUND
	RET_INVALID_ARGUMENT
	RET_DUPLICATE_ENTRY
	RET_PERMISSION_DENIED

	DB_ERR_PREPARE
	DB_ERR_EXECUTE
	DB_ERR_FETCH
	DB_ERR_TRANSACTION_BEGIN
	DB_ERR_TRANSACTION_COMMIT
	DB_ERR_UNKNOWN

	FORM_ERR_OK
	FORM_ERR_GENERIC
	FORM_ERR_SINGLE_FIELD
	FORM_ERR_MULTI_FIELD
	FORM_ERR_ENUM
	FORM_ERR_TEXTAREA
	FORM_ERR_CHECKBOX
);

# Optional export tags for organized imports
%EXPORT_TAGS = (
	exit	=> [qw(
		EXIT_OK
		EXIT_GENERIC_ERROR
		EXIT_USAGE_ERROR
		EXIT_CONFIG_ERROR
		EXIT_PENDING_FOUND
		EXIT_DB_CONNECTION_FAILED
		EXIT_FILE_NOT_FOUND
		EXIT_FILE_PERMISSION_ERROR
		EXIT_LOCK_FAILED
		EXIT_SIGNAL_CAUGHT
	)],
	return	=> [qw(
		RET_OK
		RET_GENERIC_ERROR
		RET_NOT_FOUND
		RET_INVALID_ARGUMENT
		RET_DUPLICATE_ENTRY
		RET_PERMISSION_DENIED
	)],
	database=> [qw(
		DB_ERR_PREPARE
		DB_ERR_EXECUTE
		DB_ERR_FETCH
		DB_ERR_TRANSACTION_BEGIN
		DB_ERR_TRANSACTION_COMMIT
		DB_ERR_UNKNOWN
	)],
	form	=> [qw(
		FORM_ERR_OK
		FORM_ERR_GENERIC
		FORM_ERR_SINGLE_FIELD
		FORM_ERR_MULTI_FIELD
		FORM_ERR_ENUM
		FORM_ERR_TEXTAREA
		FORM_ERR_CHECKBOX
	)],
);

# =====================================================================
# EXIT CODES (0-255 standard for Unix/Linux processes)
# =====================================================================
# These codes are used with exit() in main scripts and utilities.
# Status range 0-255 where 0 means success, 1-125 for errors,
# 126-127 reserved by shell, 128-255 for signals.

use constant EXIT_OK			=> 0;	# Successful execution
use constant EXIT_GENERIC_ERROR		=> 1;	# Generic/unspecified error
use constant EXIT_USAGE_ERROR		=> 2;	# Command line syntax error
use constant EXIT_CONFIG_ERROR		=> 3;	# Configuration/setup error
use constant EXIT_PENDING_FOUND		=> 2;	# Pending changes found (status command)
use constant EXIT_DB_CONNECTION_FAILED	=> 4;	# Database connection failed
use constant EXIT_FILE_NOT_FOUND	=> 5;	# Required file not found
use constant EXIT_FILE_PERMISSION_ERROR => 6;	# File permission error
use constant EXIT_LOCK_FAILED		=> 7;	# Lock file creation failed
use constant EXIT_SIGNAL_CAUGHT		=> 15;	# Signal caught (SIGTERM)

# =====================================================================
# FUNCTION RETURN CODES (negative for errors, zero/positive for success)
# =====================================================================
# These codes are used with return statements in functions.
# Convention: 0 or positive = success, negative = error

use constant RET_OK			=> 0;	# Function successful
use constant RET_GENERIC_ERROR		=> -1;	# Generic function error
use constant RET_NOT_FOUND		=> -2;	# Requested item not found
use constant RET_INVALID_ARGUMENT	=> -3;	# Invalid argument provided
use constant RET_DUPLICATE_ENTRY	=> -4;	# Entry already exists
use constant RET_PERMISSION_DENIED	=> -5;	# Access denied

# =====================================================================
# DATABASE-SPECIFIC ERROR CODES
# =====================================================================
# Used by Sauron::DB and related database interface functions.
# These are returned by db_exec(), db_query(), etc.

use constant DB_ERR_PREPARE		=> -1;	# SQL prepare failed
use constant DB_ERR_EXECUTE		=> -2;	# SQL execute failed
use constant DB_ERR_FETCH		=> -3;	# Row fetch failed
use constant DB_ERR_TRANSACTION_BEGIN	=> -4;	# BEGIN transaction failed
use constant DB_ERR_TRANSACTION_COMMIT	=> -5;	# COMMIT transaction failed
use constant DB_ERR_UNKNOWN		=> -99;	# Unknown database error

# =====================================================================
# FORM VALIDATION ERROR CODES
# =====================================================================
# Used by CGIutil::form_check_field() and related validation functions.
# These identify which type of form validation failed.

use constant FORM_ERR_OK		=> 0;	# No validation error
use constant FORM_ERR_GENERIC		=> 1;	# Generic form error
use constant FORM_ERR_SINGLE_FIELD	=> 1;	# Single field validation failed
use constant FORM_ERR_MULTI_FIELD	=> 2;	# Multi-field validation failed
use constant FORM_ERR_ENUM		=> 3;	# Enum field value invalid
use constant FORM_ERR_TEXTAREA		=> 13;	# Textarea validation failed
use constant FORM_ERR_CHECKBOX		=> 14;	# Checkbox group validation failed

# =====================================================================
# Helper Functions
# =====================================================================

=head1 DESCRIPTION

This module provides centralized, unique error and exit codes for use throughout
the Sauron system. It ensures consistency and prevents code duplication.

=head1 EXIT CODES

Exit codes are intended for use with exit() in main scripts. They follow Unix
conventions (0 = success, 1-125 = error, 126-127 = reserved, 128-255 = signals).

=over 4

=item EXIT_OK (0)

Successful execution without errors.

=item EXIT_GENERIC_ERROR (1)

Generic unspecified error. Used when a specific error code doesn't apply.

=item EXIT_USAGE_ERROR (2)

Command line syntax or usage error. Script was called with incorrect arguments.

=item EXIT_CONFIG_ERROR (3)

Configuration file parse error or missing required configuration.

=item EXIT_DB_CONNECTION_FAILED (4)

Database connection could not be established.

=item EXIT_FILE_NOT_FOUND (5)

Required file does not exist or cannot be read.

=item EXIT_FILE_PERMISSION_ERROR (6)

File permission denied or unsafe permissions detected.

=item EXIT_LOCK_FAILED (7)

Lock file creation failed or exclusive lock could not be obtained.

=back

=head1 RETURN CODES

Return codes are intended for use with return statements in functions.

Positive or zero values indicate success:
- 0: Normal successful completion
- Positive: Success with additional information (row count, ID, etc.)

Negative values indicate errors:
- -1: Generic error (prepare failed, not found, general failure)
- -2: Not found, execute failed, or specific error condition
- -3: Invalid argument or fetch error
- -4: Duplicate entry
- -5: Permission denied

=head1 DATABASE ERROR CODES

Database functions typically return:
- 0+: Number of rows affected (success)
- -1: SQL prepare() failed
- -2: SQL execute() failed
- -3: Row fetch failed (rare)

=head1 FORM VALIDATION CODES

Form validation functions return error codes indicating which field type failed:
- 0: Validation passed
- 1: Generic form error or single field error
- 2: Multi-field validation (arrays) failed
- 3: Enum field value invalid
- 13: Textarea validation failed
- 14: Checkbox group validation failed

=head1 USAGE EXAMPLES

  use Sauron::ErrorCodes qw(:exit);
  exit(EXIT_OK) if $success;
  exit(EXIT_CONFIG_ERROR) unless $config_valid;

  use Sauron::ErrorCodes qw(:return);
  return RET_OK if $operation_successful;
  return RET_NOT_FOUND if $item_missing;

  use Sauron::ErrorCodes;
  my $res = db_exec($sql);
  if ($res == DB_ERR_PREPARE) {
      write2log("SQL prepare failed: " . db_lasterrormsg());
  }

=head1 MODULARITY

The module supports selective importing via tags:

  use Sauron::ErrorCodes qw(:exit);    # Import only exit codes
  use Sauron::ErrorCodes qw(:return);  # Import only return codes
  use Sauron::ErrorCodes qw(:database);# Import only database codes
  use Sauron::ErrorCodes qw(:form);    # Import only form codes
  use Sauron::ErrorCodes;              # Import all codes

=cut

1;
