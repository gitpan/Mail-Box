
use strict;
use warnings;

package Mail::Message::TransferEnc::Base64;
use vars '$VERSION';
$VERSION = '2.044';
use base 'Mail::Message::TransferEnc';

use MIME::Base64;


sub name() { 'base64' }

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------


sub decode($@)
{   my ($self, $body, %args) = @_;

    my $lines
      = $body->isa('Mail::Message::Body::File')
      ? $self->_decode_from_file($body)
      : $self->_decode_from_lines($body);

    unless($lines)
    {   $body->transferEncoding('none');
        return $body;
    }
 
    my $bodytype
      = defined $args{result_type} ? $args{result_type}
      : $body->isBinary            ? 'Mail::Message::Body::File'
      :                              ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => $lines
     );
}

sub _decode_from_file($)
{   my ($self, $body) = @_;
    local $_;

    my $in = $body->file || return;
    my $unpacked = decode_base64(join '', $in->getlines);
    $in->close;
    $unpacked;
}

sub _decode_from_lines($)
{   my ($self, $body) = @_;
    join '', map { decode_base64($_) } $body->lines;
}

#------------------------------------------

sub encode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'base64'
     , data              => encode_base64($body->string)
     );
}

#------------------------------------------

1;
