#!/usr/bin/perl -w
#
# Encoding and Decoding of Base64
# Could use some more tests....
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message;
use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::Base64;
use Tools;
use IO::Scalar;

BEGIN { plan tests => 12 }

my $decoded = <<DECODED;
This text is used to test base64 encoding and decoding.  Let
see whether it works.
DECODED

my $encoded = <<ENCODED;
VGhpcyB0ZXh0IGlzIHVzZWQgdG8gdGVzdCBiYXNlNjQgZW5jb2RpbmcgYW5kIGRlY29kaW5nLiAg
TGV0CnNlZSB3aGV0aGVyIGl0IHdvcmtzLgo=
ENCODED

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , checked   => 1
  , transfer_encoding => 'base64'
  , data      => $encoded
  );

ok(defined $body);

my $dec = $body->encode(transfer_encoding => 'none');
ok(defined $dec);
ok($dec->isa('Mail::Message::Body'));
ok(!$dec->checked);
ok($dec->string eq $decoded);
ok($dec->transferEncoding eq 'none');

my $enc = $dec->encode(transfer_encoding => '7bit');
ok(defined $enc);
ok($enc->isa('Mail::Message::Body'));
ok($enc->checked);
ok($enc->string eq $decoded);

my $msg = Mail::Message->buildFromBody($enc, From => 'me', To => 'you',
   Date => 'now');
ok($msg);

my $fakeout;
my $g = IO::Scalar->new(\$fakeout);
$msg->print($g);

ok($fakeout eq <<'MSG');
From: me
To: you
Date: now
Content-Type: text/html; charset="us-ascii"
Content-Length: 83
Lines: 2
Content-Transfer-Encoding: 7bit

This text is used to test base64 encoding and decoding.  Let
see whether it works.
MSG