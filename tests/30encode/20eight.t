#!/usr/bin/perl -T
#
# Encoding and Decoding of 8bit
#

use Test::More;
use strict;
use warnings;

use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::EightBit;
use Tools;

BEGIN { plan tests => 6 }

my $decoded = <<DECODED;
yefoiuh��sjhkw284���Ue\000iouoi\013wei
sdful����jlkjliua\000aba
DECODED

my $encoded = <<ENCODED;
yefoiuh��sjhkw284���Ueiouoiwei
sdful����jlkjliuaaba
ENCODED

my $codec = Mail::Message::TransferEnc::EightBit->new;
ok(defined $codec);
is($codec->name, '8bit');

# Test encoding

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , data      => $decoded
  );

my $enc    = $codec->encode($body);
ok($body!=$enc);
is($enc->mimeType, 'text/html');
is($enc->transferEncoding, '8bit');
is($enc->string, $encoded);

# Test decoding

