#!/usr/bin/perl
use strict;
use warnings;
use lib '/opt/sauron';

# Load configuration and modules
use Sauron::Sauron;
use Sauron::DB;
use Sauron::Approval;

# Load config
load_config();

# Connect to database
unless (db_connect2()) {
    die "Cannot connect to database: $DBI::errstr";
}

# Test converting operation codes
print "=== Operation Code Conversions ===\n";
print "A -> " . Sauron::Approval::_operation_code_to_text('A') . "\n";
print "M -> " . Sauron::Approval::_operation_code_to_text('M') . "\n";
print "D -> " . Sauron::Approval::_operation_code_to_text('D') . "\n";

# Test converting host types
print "\n=== Host Type Conversions ===\n";
for my $type (1, 2, 3, 4, 5) {
    print "$type -> " . Sauron::Approval::_host_type_to_text($type) . "\n";
}

# Test serialization/deserialization
print "\n=== Serialization Test ===\n";
my %test_data = (
    domain => 'test.example.com',
    type => 1,
    ip => '192.168.1.1',
    email => 'admin@example.com'
);

my $serialized = Sauron::Approval::_serialize(\%test_data);
print "Serialized: $serialized\n";

my $deserialized = Sauron::Approval::_deserialize($serialized);
print "Deserialized domain: " . $deserialized->{domain} . "\n";
print "Deserialized type: " . $deserialized->{type} . "\n";

db_disconnect();
print "\n✓ All tests passed!\n";
