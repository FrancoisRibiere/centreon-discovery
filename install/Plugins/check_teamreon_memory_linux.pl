#! /usr/bin/perl -w
###################################################################
# Oreon is developped with GPL Licence 2.0 
#
# GPL License: http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#
# Developped by : Julien Mathis - Romain Le Merlus 
#                 Mathavarajan Sugumaran
#
###################################################################
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
#    For information : contact@merethis.com
####################################################################
#
# Script init
#

use strict;
use Net::SNMP qw(:snmp);
use FindBin;
use lib "$FindBin::Bin";
use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);

if (eval "require centreon" ) {
	use centreon qw(get_parameters);
	use vars qw($VERSION %centreon);
	%centreon=get_parameters();
} else {
	print "Unable to load centreon perl module\n";
    exit $ERRORS{'UNKNOWN'};
}

use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_V $opt_h $opt_g $opt_v $opt_C $opt_w $opt_c $opt_s $opt_H @test);
my $pathtorrdbase = $centreon{GLOBAL}{DIR_RRDTOOL};

##
## Plugin var init
##

my ($hrStorageDescr, $hrStorageAllocationUnits, $hrStorageSize, $hrStorageUsed);
my ($AllocationUnits, $Size, $Used);
my ($tot, $used, $pourcent, $return_code);

$PROGNAME = "$0";
sub print_help ();
sub print_usage ();
Getopt::Long::Configure('bundling');
GetOptions
    ("h"   => \$opt_h, "help"         => \$opt_h,
     "V"   => \$opt_V, "version"      => \$opt_V,
     "v=s" => \$opt_v, "snmp=s"       => \$opt_v,
     "C=s" => \$opt_C, "community=s"  => \$opt_C,
     "w=s" => \$opt_w, "warning=s"    => \$opt_w,
     "c=s" => \$opt_c, "critical=s"   => \$opt_c,
     "s=s" => \$opt_s, "swap=s"       => \$opt_s,
     "H=s" => \$opt_H, "hostname=s"   => \$opt_H);


if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 1.2 $');
    exit $ERRORS{'OK'};
}

if ($opt_h) {
	print_help();
	exit $ERRORS{'OK'};
}

$opt_H = shift unless ($opt_H);
(print_usage() && exit $ERRORS{'OK'}) unless ($opt_H);


($opt_v) || ($opt_v = shift) || ($opt_v = "2");
my $snmp = $1 if ($opt_v =~ /(\d)/);

($opt_C) || ($opt_C = shift) || ($opt_C = "public");

($opt_c) || ($opt_c = shift) || ($opt_c = 95);
my $critical = $1 if ($opt_c =~ /([0-9]+)/);

($opt_w) || ($opt_w = shift) || ($opt_w = 80);
my $warning = $1 if ($opt_w =~ /([0-9]+)/);
if ($critical <= $warning){
    print "(--crit) must be superior to (--warn)";
    print_usage();
    exit $ERRORS{'OK'};
}

my $swap_limit;
if ($opt_s)
{
    ($opt_s) || ($opt_s = shift) || ($opt_s = 10);
    $swap_limit = $1 if ($opt_s =~ /([0-9]+)/);
}

my $start=time;
my $name = $0;

## Plugin snmp requests

# my $OID_hrStorageDescr = $centreon{MIB2}{HR_STORAGE_DESCR};
# my $OID_hrStorageAllocationUnits =$centreon{MIB2}{HR_STORAGE_ALLOCATION_UNITS};
# my $OID_hrStorageSize =$centreon{MIB2}{HR_STORAGE_SIZE};
# my $OID_hrStorageUsed =$centreon{MIB2}{HR_STORAGE_USED};

# create a SNMP session

my ( $session, $error ) = Net::SNMP->session(-hostname  => $opt_H,-community => $opt_C, -version  => $snmp);
if ( !defined($session) ) {
    print("CRITICAL: SNMP Session : $error");
    exit $ERRORS{'CRITICAL'};
}

####################
#### snmp request
##

my $OID_descr_storage = ".1.3.6.1.2.1.25.2.3.1.3"; #"1.3.6.1.2.1.25.2.3.1.1";
my $result = $session->get_table(Baseoid => $OID_descr_storage);
if (!defined($result)) {
    printf("ERROR: Description Table hrStorageType : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}

my ($virt_alloc, my $virt_used, my $virt_size);

my $indexV = 0;
my $indexR = 0;
foreach my $key (oid_lex_sort(keys %$result)) {
    if  ($result->{$key} =~ m/Swap|Virtual/) {
	my @cpt = split /\./,$key;
	$indexV = $cpt[scalar(@cpt) - 1];;
    }
    if  ($result->{$key} =~ m/Real|Physical/) {
	my @cpt = split /\./,$key;
	$indexR = $cpt[scalar(@cpt)-1];
    }
}
if ($indexV == 0 || $indexR == 0) {
    printf("ERROR: cannot find ram information");
    exit $ERRORS{'UNKNOWN'}; 
}
my $OID_hrStorage_used = ".1.3.6.1.2.1.25.2.3.1.6";
my $OID_Swap_storage_used = ".1.3.6.1.2.1.25.2.3.1.6.".$indexV;
my $OID_RealM_storage_used = ".1.3.6.1.2.1.25.2.3.1.6.".$indexR;

my $used_mem = $session->get_table(Baseoid => $OID_hrStorage_used);
if (!defined($used_mem)) {
    printf("ERROR: Description Table hrStorageUsed : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}

my $OID_hrStorage_size = ".1.3.6.1.2.1.25.2.3.1.5";
my $OID_Swap_storage_size = ".1.3.6.1.2.1.25.2.3.1.5.".$indexV;
my $OID_RealM_storage_size = ".1.3.6.1.2.1.25.2.3.1.5.".$indexR;

my $total_mem = $session->get_table(Baseoid => $OID_hrStorage_size);
if (!defined($total_mem)) {
    printf("ERROR: Description Table hrStorageSize : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}

my $OID_storage_allocationUnits = ".1.3.6.1.2.1.25.2.3.1.4"; 
my $OID_Swap_storage_allocationUnits = ".1.3.6.1.2.1.25.2.3.1.4.".$indexV;
my $OID_RealM_storage_allocationUnits = ".1.3.6.1.2.1.25.2.3.1.4.".$indexR;
my $alloc_units = $session->get_table(Baseoid => $OID_storage_allocationUnits);
if (!defined($alloc_units)) {
    printf("ERROR: Description Table hrStorageUsed : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}
my $swap_used = $used_mem->{$OID_Swap_storage_used} * $alloc_units->{$OID_Swap_storage_allocationUnits};
my $realM_used = $used_mem->{$OID_RealM_storage_used} * $alloc_units->{$OID_RealM_storage_allocationUnits};

my $swap_size = $total_mem->{$OID_Swap_storage_size} * $alloc_units->{$OID_Swap_storage_allocationUnits};
my $realM_size = $total_mem->{$OID_RealM_storage_size} * $alloc_units->{$OID_RealM_storage_allocationUnits};
my $total_memory_used = $swap_used + $realM_used;
my $total_memory_size = $swap_size + $realM_size;

# percentage of total, physical and swap  memory used

if ($swap_size eq "0"){
    $swap_size = 1;
}

my $percent_used = ($total_memory_used/$total_memory_size)*100;
my $percent_swap_used = ($swap_used/$swap_size) * 100;
my $percent_realM_used = ($realM_used/$realM_size) * 100;
$percent_swap_used =~ s/\.[0-9]+//;
$percent_used =~ s/\.[0-9]+//;
$percent_realM_used =~ s/\.[0-9]+//;

# return

if(($opt_s) && ($opt_s =~ /([0-9]+)/))
{
    if(($percent_realM_used >= 99) && ($percent_swap_used > $swap_limit))
    {
	print "swap threshold (".$opt_s."%) excedeed : total memory used : ".$percent_used."%, ram used : ".$percent_realM_used."%, swap used : ".$percent_swap_used."% | used=".$total_memory_used."o size=".$total_memory_size."o\n";
	exit $ERRORS{'CRITICAL'};
    }
}

if ($percent_used >= $opt_c){
    print "threshold (".$opt_c."%) excedeed : total memory used : ".$percent_used."%, ram used : ".$percent_realM_used."%, swap used : ".$percent_swap_used."% | used=".$total_memory_used."o size=".$total_memory_size."o\n";
    exit $ERRORS{'CRITICAL'};
} elsif ($percent_used >= $opt_w){
    print "threshold (".$opt_w."%) excedeed : total memory used : ".$percent_used."%, ram used : ".$percent_realM_used."%, swap used ".$percent_swap_used."% | used=".$total_memory_used."o size=".$total_memory_size."o\n";
    exit $ERRORS{'WARNING'};	
} else {
    print "total memory used : ".$percent_used."%  ram used : ".$percent_realM_used."%, swap used ".$percent_swap_used."% | used=".$total_memory_used."o size=".$total_memory_size."o\n";
    exit $ERRORS{'OK'};
}

sub print_usage () {
    print "\nUsage:\n";
    print "$PROGNAME\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public,\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
    print "                        2 for SNMP v2c\n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n";
    print "   -c (--critical)   percentage of memory used at which a critical message will be generated\n";
    print "   -w (--warning)    percentage of memory used at which a warning message will be generated\n";
    print "   -s (--swap)       limit of swap memory can reach before the service turns critical, while phyical memory is near 100%\n";    
}

sub print_help () {
    print "#=========================================\n";
	print "#  Copyright (c) 2007 Merethis SARL      =\n";
	print "#  Developped by Julien Mathis           =\n";
	print "#  Bugs to http://www.oreon-project.org/ =\n";
	print "#=========================================\n";
	print_usage();
	print "\n";
}