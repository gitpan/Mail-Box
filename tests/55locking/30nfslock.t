#!/usr/bin/perl -T
#
# Test the locking methods.
#

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More;
use File::Spec;

use Mail::Box::Locker::NFS;

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

BEGIN {
   if($windows)
   {   plan skip_all => "not available on MicroSoft Windows.";
       exit 0;
   }

   plan tests => 7;
}

my $lockfile  = File::Spec->catfile('folders', 'lockfiletest');
unlink $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'nfs'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker);
is($locker->name, 'NFS');

ok($locker->lock);
ok(-f $lockfile);
ok($locker->hasLock);

# Already got lock, so should return immediately.
my $warn = '';
{  $SIG{__WARN__} = sub {$warn = "@_"};
   $locker->lock;
}
ok($warn =~ m/already locked over nfs/i, 'relock no problem');

$locker->unlock;
ok(not $locker->hasLock);
