
use strict;
use warnings;

package Mail::Message::TransferEnc::SevenBit;
use vars '$VERSION';
$VERSION = '2.041';
use base 'Mail::Message::TransferEnc';


sub name() { '7bit' }

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------

sub decode($@)
{   my ($self, $body, %args) = @_;
    $body->transferEncoding('none');
    $body;
}

#------------------------------------------

sub encode($@)
{   my ($self, $body, %args) = @_;

    my @lines;
    my $changes = 0;

    foreach ($body->lines)
    {   $changes++ if s/[^\000-\127]/chr(ord($&) & 0x7f)/ge;
        $changes++ if s/[\000\013]//g;

        $changes++ if length > 997;
        push @lines, substr($_, 0, 996, '')."\n"
            while length > 997;

        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('7bit');
        return $body;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => '7bit'
     , data              => \@lines
     );
}

#------------------------------------------

1;
