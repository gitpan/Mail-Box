use strict;
use warnings;

package Mail::Message::TransferEnc::Base64;
our $VERSION = 2.029;  # Part of Mail::Box
use base 'Mail::Message::TransferEnc';

sub name() { 'base64' }

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

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

    my @unpacked;
    while($in->getline)
    {   tr|A-Za-z0-9+=/||cd;   # remove non-base64 chars
        next unless length;

        if(length % 4)
        {   $self->log(WARNING => "Base64 line length not padded on 4.");
            return undef;
        }

        s/=+$//;               # remove padding
        tr|A-Za-z0-9+/| -_|;   # convert to uuencoded format
        push @unpacked, unpack 'u*', $_;
    }
    $in->close;

    join '', @unpacked;
}

sub _decode_from_lines($)
{   my ($self, $body) = @_;
    my @lines = $body->lines;

    my @unpacked;
    foreach (@lines)
    {   tr|A-Za-z0-9+=/||cd;   # remove non-base64 chars
        next unless length;

        unless(length % 4)
        {   $self->log(WARNING => "Base64 line length not padded on 4.");
            return undef;
        }

        s/=+$//;               # remove padding
        tr|A-Za-z0-9+/| -_|;   # convert to uuencoded format
        push @unpacked, unpack 'u', (chr 32+length($_)*3/4).$_;
    }

    join '', @unpacked;
}

sub encode($@)
{   my ($self, $body, %args) = @_;

    local $_;
    my $in = $body->file || return $body;
    binmode $in, ':raw' if ref $in eq 'GLOB' || $in->can('BINMODE');

    my (@lines, $bytes);

    while(my $read = $in->read($bytes, 57))
    {   for(pack 'u57', $bytes)
        {   s/^.//;
            tr|` -_|AA-Za-z0-9+/|;

            if(my $align = $read % 3)
            {    if($align==1) { s/..$/==/ } else { s/.$/=/ }
            }

            push @lines, $_;
        }
    }

    $in->close;

    my $bodytype = $args{result_type} || ref $body;
    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'base64'
     , data              => \@lines
     );
}

1;
