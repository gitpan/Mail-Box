#!/usr/bin/perl -w

#
# Test creation/deletion and listing of folders.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Mbox;
use Mail::Box::MH;
use Mail::Message::Construct;

use Tools;

use Test;
use File::Copy;
use File::Spec;

BEGIN {plan tests => 18}

my $src = File::Spec->catfile('t', 'mbox.src');
my $top = File::Spec->catfile('t', 'Mail');
clean_dir $top;

my $mbox = Mail::Box::Mbox->new
  ( folder      => $src
  , folderdir   => 't'
  , lock_type   => 'NONE'
  );

#
# Create a nice structure which looks like a set of MH folders.
#

sub folder($;$@)
{   my $dirname = shift;
    $dirname = File::Spec->catfile($dirname, shift) if @_;

    die "Cannot create directory $dirname: $!\n"
        unless -d $dirname || mkdir $dirname, 0700;

    foreach (@_)
    {   my $f = File::Spec->catfile($dirname, $_);
        open CREATE, ">$f" or die "Cannot create $f: $!\n";
        $mbox->message($_)->print(\*CREATE) if m/^\d+$/;
        close CREATE;
    }
    $dirname;
}

folder $top;
folder $top, 'f1', qw/a b c/;
folder $top, 'f2', 1, 2, 3;       # only real folder
folder $top, 'f3';                # empty folder

my $sub1 = folder $top, 'sub1';
folder $sub1, 's1f1';
folder $sub1, 's1f2';
folder $sub1, 's1f3';
folder $top,  'sub2';            # empty dir
my $f4 = folder $top, 'f4', 1, 2, 3;
folder $f4, 'f4f1';
unpack_mbox $src, File::Spec->catfile($f4, 'f4f2');
folder $f4, 'f4f3';

ok(cmplists [ sort Mail::Box::MH->listSubFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listSubFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listSubFolders
                     ( folderdir  => $top
                     , skip_empty => 1
                     ) ]
          , [ qw/f2 f4 sub1/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listSubFolders
                     ( folderdir  => $top
                     , check      => 1
                     ) ]
          , [ qw/f2 f4/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listSubFolders
                     ( folderdir  => $top
                     , folder     => "=f4"
                     )
            ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listSubFolders(folderdir  => "$top/f4") ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

#
# Open a folder in a sub-dir which uses the extention.
#

my $folder = Mail::Box::MH->new
  ( folderdir   => $top
  , folder      => '=f4/f4f2'
  , lock_type   => 'NONE'
  );

ok($folder);
ok($folder->messages==45);
$folder->close;

#
# Open a new folder.
#

my $newfolder = File::Spec->catfile($f4, 'newfolder');
ok(! -d $newfolder);
Mail::Box::MH->create('=f4/newfolder', folderdir  => $top);
ok(-d $newfolder);

$folder = Mail::Box::MH->new
  ( folderdir   => $top
  , folder      => '=f4/newfolder'
  , access      => 'rw'
  , keep_index  => 1
  , lock_type   => 'NONE'
  );

ok($folder);
ok($folder->messages==0);

my $msg = Mail::Message->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , data    => [ "a short message\n", "of two lines.\n" ]
  );

$folder->addMessage($msg);
ok($folder->messages==1);
$folder->close;
ok(-f File::Spec->catfile($newfolder, '1'));

opendir DIR, $newfolder or die "Cannot read directory $newfolder: $!\n";
my @all = grep !/^\./, readdir DIR;
closedir DIR;
ok(@all==1);

my $seq = File::Spec->catfile($newfolder, '.mh_sequences');
open SEQ, $seq or die "Cannot read $seq: $!\n";
my @seq = <SEQ>;
close SEQ;

ok(@seq==1);
ok($seq[0],"unseen: 1\n");

#
# Delete a folder.
#

$folder = Mail::Box::MH->new
  ( folderdir   => $top
  , folder      => '=f4'
  , access      => 'rw'
  , lock_type   => 'NONE'
  , keep_index  => 1
  );

ok(-d $f4);
$folder->delete;
$folder->close;

clean_dir $top;