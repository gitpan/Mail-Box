
use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
use vars '$VERSION';
$VERSION = '2.058';
use base 'Mail::Message::TransferEnc';

use MIME::QuotedPrint;


sub name() { 'quoted-printable' }

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------


sub decode($@)
{   my ($self, $body, %args) = @_;

    my @lines    = map decode_qp($_), $body->lines;
    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

#------------------------------------------


sub encode($@)
{   my ($self, $body, %args) = @_;

    my @lines    = map encode_qp($_), $body->lines;
    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'quoted-printable'
     , data              => \@lines
     );
}

#------------------------------------------

1;
