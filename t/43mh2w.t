#!/usr/bin/perl -w

#
# Test writing of MH folders.
#

use strict;
use lib qw(. t);
use Mail::Box::MH;
use Mail::Box::Mbox;
use Tools;

use Test;
use File::Compare;
use File::Copy;

BEGIN {plan tests => 56}

my $mhsrc = File::Spec->catfile('t', 'mh.src');

clean_dir $mhsrc;
unpack_mbox2mh($src, $mhsrc);

my $folder = new Mail::Box::MH
  ( folder     => $mhsrc
  , folderdir  => 't'
  , lock_type  => 'NONE'
  , extract    => 'LAZY'
  , access     => 'rw'
  , keep_index => 1
  );

ok(defined $folder);
ok($folder->messages==45);

my $msg3 = $folder->message(3);

# Nothing yet...

$folder->modified(1);
$folder->write(renumber => 0);

ok(cmplists [sort {$a cmp $b} listdir $mhsrc],
            [sort {$a cmp $b} '.mh_sequences', 1..12, 14..46]
  );

$folder->modified(1);
$folder->write(renumber => 1);

ok(cmplists [sort {$a cmp $b} listdir $mhsrc],
            [sort {$a cmp $b} '.mh_sequences', 1..45]
  );

$folder->message(2)->delete;
ok($folder->message(2)->isDelayed);
ok(defined $folder->message(3)->get('subject')); # load, creates index

$folder->write;
ok(cmplists [sort {$a cmp $b} listdir $mhsrc],
            [sort {$a cmp $b} '.index', '.mh_sequences', 1..44]
  );
ok($folder->messages==44);

$folder->message(8)->delete;
ok($folder->message(8)->deleted);
ok($folder->messages==44);

$folder->write(keep_deleted => 1);
ok($folder->message(8)->deleted);
ok($folder->messages==44);

$folder->write;
ok($folder->messages==43);
foreach ($folder->messages) { ok(! $_->deleted) }

$folder->close;

clean_dir $mhsrc;
