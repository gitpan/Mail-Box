
use strict;
use warnings;

package Mail::Message::TransferEnc::Binary;
use vars '$VERSION';
$VERSION = '2.055';
use base 'Mail::Message::TransferEnc';


sub name() { 'binary' }

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
    foreach ($self->lines)
    {   $changes++ if s/[\000\013]//g;
        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('none');
        return $body;
    }

    my $bodytype = $args{result_type} || ref($self->load);

    $bodytype->new
     ( based_on          => $self
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

#------------------------------------------

1;
