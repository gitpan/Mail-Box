#!/usr/bin/perl -T
#
# Test flags conversion of IMAP4 folders.

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More;
use Mail::Transport::IMAP4;

my $mti = 'Mail::Transport::IMAP4';

BEGIN
{   eval { require Mail::IMAPClient };
    if($@ =~ m/Can't locate/)
    {   plan skip_all => 'requires Mail::IMAPClient';
        exit(0);
    }
    
    eval { require Digest::HMAC_MD5 };
    if($@ =~ m/Can't locate/)
    {   plan skip_all => 'requires Digest::HMAC_MD5';
        exit(0);
    }

    plan tests => 43;
}

###
### Checking labels2flags
###

sub expect_flags($$$)
{   my ($got, $expect, $text) = @_;
    my $errors = 0;

    my %got;
    $got{$_}++ for split " ", $got;

    if(grep {$_ > 1} values %got)
    {   $errors++;
        ok(0, "found double, $text");
    }
    else
    {   ok(1, $text);
    }

    foreach my $e (split " ", $expect)
    {   if(delete $got{$e}) { ok(1, "found $e")   }
        else { $errors++;     ok(0, "missing $e") }
    }

    if(keys %got)
    {   ok(0, "got too much: ".join(" ", keys %got));
        $errors++;
    }
    else
    {   ok(1, "exact match");
    }

    if($errors)
    {   warn "$errors errors, expected '$expect' got '$got'\n";
    }
}

my $flags = $mti->labelsToFlags();
expect_flags($flags, '', "Empty set");

$flags = $mti->labelsToFlags(seen => 1, flagged => 1, old => 1);
expect_flags($flags, '\Seen \Flagged', "No old");

$flags = $mti->labelsToFlags( {seen => 1, flagged => 1, old => 1} );
expect_flags($flags, '\Seen \Flagged', "No old as hash");

$flags = $mti->labelsToFlags(seen => 1, flagged => 1, old => 0);
expect_flags($flags, '\Seen \Flagged \Recent', "No old");

$flags = $mti->labelsToFlags( {seen => 1, flagged => 1, old => 0} );
expect_flags($flags, '\Seen \Flagged \Recent', "No old as hash");

$flags = $mti->labelsToFlags(seen => 1, replied => 1, flagged => 1,
  deleted => 1, draft => 1, old => 0, spam => 1);
expect_flags($flags, '\Seen \Answered \Flagged \Deleted \Draft \Recent \Spam',
   "show all flags");

$flags = $mti->labelsToFlags(seen => 0, replied => 0, flagged => 0,
  deleted => 0, draft => 0, old => 1, spam => 0);
expect_flags($flags, '', "show no flags");

###
### Checking flagsToLabels
###

sub expect_labels($$$)
{   my ($got, $expect, $text) = @_;

    my $gotkeys = join " ", %$got;
    my $expkeys = join " ", %$expect;
    my $errors  = 0;

    foreach my $e (keys %$expect)
    {      if(!exists $got->{$e})  { $errors++; ok(0, "missing $e") }
        else { $errors += (($got->{$e}||0) != $expect->{$e});
               cmp_ok((delete $got->{$e})||0, '==',  $expect->{$e});
             }
    }

    if(keys %$got)
    {   ok(0, "got too much: ".join(" ", keys %$got));
        $errors++;
    }
    else
    {   ok(1, "exact match");
    }

    if($errors)
    {   warn "$errors errors, expected '$expkeys' got '$gotkeys'\n";
    }
}

my $labels = $mti->flagsToLabels();
expect_labels($labels, {}, "flagsToLabels: Empty set");

$labels = $mti->flagsToLabels( qw[\Seen \Flagged] );
expect_labels($labels, {seen => 1, flagged => 1}, "flagsToLabels: Empty set");

$labels = $mti->flagsToLabels( qw[\Seen \Answered \Flagged \Deleted
                                  \Draft \Recent \Spam] );

expect_labels $labels
              , { seen => 1, replied => 1, flagged => 1, deleted => 1
                , draft => 1, old => 0, spam => 1
                }
              , "show all labels";

exit 0;