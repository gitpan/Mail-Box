#!/usr/bin/perl -w

#
# Test the locking methods.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Locker::Flock;
use Tools;

use Test;
use File::Spec;

BEGIN {plan tests => 7}

my $lockfile  = File::Spec->catfile('t', 'lockfiletest');
unlink $lockfile;
open OUT, '>', $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'FLOCK'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 );

ok($locker);
ok($locker->name eq 'FLOCK');

ok($locker->lock);
ok(-f $lockfile);
ok($locker->hasLock);

# Already got lock, so should return immediately.
ok($locker->lock);

$locker->unlock;
ok(not $locker->hasLock);

close OUT;
unlink $lockfile;