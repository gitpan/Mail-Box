use strict;
use warnings;

package Mail::Message::TransferEnc;
our $VERSION = 2.027;  # Part of Mail::Box
use base 'Mail::Reporter';

my %encoder =
 ( base64 => 'Mail::Message::TransferEnc::Base64'
 , '7bit' => 'Mail::Message::TransferEnc::SevenBit'
 , '8bit' => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 );

sub create($@)
{   my ($class, $type) = (shift, shift);

    my $encoder = $encoder{lc $type};
    unless($encoder)
    {   $class->new(@_)->log(WARNING => "No decoder for $type");
        return;
    }

    eval "require $encoder";
    if($@)
    {   $class->new(@_)->log(WARNING => "Decoder for $type does not work:\n$@");
        return;
    }

    $encoder->new(@_);
}

sub addTransferEncoder($$)
{   my ($class, $type, $encoderclass) = @_;
    $encoder{lc $type} = $encoderclass;
    $class;
}

sub name {shift->notImplemented}

sub check($@) {shift->notImplemented}

sub decode($@) {shift->notImplemented}

sub encode($) {shift->notImplemented}

1;
