#!/usr/bin/perl

# Demonstration of a simple search.
#
# This code can be used and modified without restriction.
# Mark Overmeer, <mailbox@overmeer.net>, 17 feb 2002
# Updated 16 jan 2003 to work more like unix-grep syntax

use warnings;
use strict;
use lib '..', '.';

use Mail::Box::Manager 2.008;
use Mail::Box::Search::Grep;

#
# Get the command line arguments.
#

die "Usage: $0 pattern mailboxes\n"
    unless @ARGV >= 2;

my ($pattern, @mailboxes) = @ARGV;

my $mgr = Mail::Box::Manager->new;

foreach my $mailbox (@mailboxes)
{   my $folder = $mgr->open($mailbox
#, extract => 'ALWAYS'
        );

#my $msg0 = $folder->message(0);
#warn "a: ",$msg0->isDelayed;
#warn "1: ", $_->isDelayed foreach $msg0->parts;

#my $msg = $folder->message(1);
#warn "b: ", $msg->isDelayed;
#warn "1: ", $_->isDelayed foreach $msg->parts;
#warn "2: ",$_->isDelayed foreach ($msg->parts)[1]->parts;
    unless(defined $folder)
    {   warn "*** Cannot open folder $mailbox.\n";
        next;
    }

    $_->printStructure
        foreach $folder->messages;
    
    print "*** Scanning through $mailbox\n"
       if @mailboxes > 1;

    my $grep = Mail::Box::Search::Grep->new
      ( in      => 'MESSAGE'
      , match   => qr/$pattern/
      , details => 'PRINT'
      );

    $grep->search($folder);
    $folder->close;
}
