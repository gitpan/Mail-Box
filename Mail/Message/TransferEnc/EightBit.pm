use strict;
use warnings;

package Mail::Message::TransferEnc::EightBit;
our $VERSION = 2.040;  # Part of Mail::Box
use base 'Mail::Message::TransferEnc';

sub name() { '8bit' }

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

sub decode($@)
{   my ($self, $body, %args) = @_;
    $body->transferEncoding('none');
    $body;
}

sub encode($@)
{   my ($self, $body, %args) = @_;

    my @lines;
    my $changes = 0;

    foreach ($body->lines)
    {   $changes++ if s/[\000\013]//g;

        $changes++ if length > 997;
        push @lines, substr($_, 0, 996, '')."\n"
            while length > 997;

        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('8bit');
        return $body;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => '8bit'
     , data              => \@lines
     );
}

1;
