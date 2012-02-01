#!/usr/bin/perl
# Just a module test script for Bugger::Lookup
use Bugger::Lookup;
use strict;
use Data::Dumper::Simple;

my $bugger = new Bugger::Lookup;
my @array = $bugger->package("xchat");
print Dumper (@array);

