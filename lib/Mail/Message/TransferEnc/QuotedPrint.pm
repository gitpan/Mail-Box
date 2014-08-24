# Copyrights 2001-2014 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.

use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
use vars '$VERSION';
$VERSION = '2.117';

use base 'Mail::Message::TransferEnc';

use MIME::QuotedPrint;


sub name() { 'quoted-printable' }

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}


sub decode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => decode_qp($body->string)
     );
}


sub encode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'quoted-printable'
     , data              => encode_qp($body->string)
     );
}

1;
