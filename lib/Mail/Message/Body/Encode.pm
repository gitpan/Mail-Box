# Copyrights 2001-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.

use strict;
use warnings;

package Mail::Message::Body;
use vars '$VERSION';
$VERSION = '2.082';

use base 'Mail::Reporter';

use Carp;

use MIME::Types;
use File::Basename 'basename';

my MIME::Types $mime_types;


sub encode(@)
{   my ($self, %args) = @_;

    # simplify the arguments

    my $type_from = $self->type;
    my $type_to   = $args{mime_type} || $type_from->clone;
    $type_to = Mail::Message::Field->new('Content-Type' => $type_to)
        unless ref $type_to;

    if(my $charset = delete $args{charset})
    {   # Charset conversions are ignored for now.
        $type_to->attribute(charset => $charset);
    }

    my $transfer = $args{transfer_encoding} || $self->transferEncoding->clone;
    $transfer    = Mail::Message::Field->new('Content-Transfer-Encoding' =>
         $transfer) unless ref $transfer;

    # What will we do?
#   my $mime_was  = lc $type_from;
#   my $mime_to   = lc $type_to;

# If possible, update unify() too.
#   my $char_was  = $type_from->attribute('charset');
#   my $char_to   = $type_to->attribute('charset');

    my $trans_was = lc $self->transferEncoding;
    my $trans_to  = lc $transfer;

    #
    # The only translations implemented now is content transfer encoding.
    #

#warn "Translate ($trans_was) -> ($trans_to)\n";
    return $self if $trans_was eq $trans_to;

    my $bodytype  = $args{result_type} || ref $self;

    my $decoded;
    if($trans_was eq 'none') {$decoded = $self}
    elsif(my $decoder = $self->getTransferEncHandler($trans_was))
    {   $decoded = $decoder->decode($self, result_type => $bodytype) }
    else
    {   $self->log(WARNING =>
           "No decoder defined for transfer encoding $trans_was.");
        return $self;
    }

    my $encoded;
    if($trans_to eq 'none') {$encoded = $decoded}
    elsif(my $encoder = $self->getTransferEncHandler($trans_to))
    {   $encoded = $encoder->encode($decoded, result_type => $bodytype) }
    else
    {   $self->log(WARNING =>
           "No encoder defined for transfer encoding $trans_to.");
        return $decoded;
    }
    $encoded;
}

#------------------------------------------


sub check()
{   my $self     = shift;
    return $self if $self->checked;
    my $eol      = $self->eol;

    my $encoding = $self->transferEncoding->body;
    return $self->eol($eol)
       if $encoding eq 'none';

    my $encoder  = $self->getTransferEncHandler($encoding);

    my $checked
      = $encoder
      ? $encoder->check($self)->eol($eol)
      : $self->eol($eol);

    $checked->checked(1);
    $checked;
}

#------------------------------------------


sub encoded()
{   my $self = shift;

    return $self->check
        unless $self->transferEncoding eq 'none';

    $mime_types ||= MIME::Types->new;

    my $mime = $mime_types->type($self->type->body);
    $self->encode(transfer_encoding =>
         defined $mime ? $mime->encoding : 'base64');
}

#------------------------------------------


sub unify($)
{   my ($self, $body) = @_;
    return $self if $self==$body;

    my $mime     = $self->type;
    my $transfer = $self->transferEncoding;

    my $encoded  = $body->encode
     ( mime_type         => $mime
     , transfer_encoding => $transfer
     );

    # Encode makes the best of it, but is it good enough?

    my $newmime     = $encoded->type;
    return unless $newmime  eq $mime;
    return unless $transfer eq $encoded->transferEncoding;

# Character transformation not possible yet.
#   my $want_charset= $mime->attribute('charset')    || '';
#   my $got_charset = $newmime->attribute('charset') || '';
#   return unless $want_charset eq $got_charset;

    $encoded;
}

#------------------------------------------


sub isBinary()
{   my $self = shift;
    $mime_types ||= MIME::Types->new(only_complete => 1);
    my $type = $self->type                    or return 1;
    my $mime = $mime_types->type($type->body) or return 1;
    $mime->isBinary;
}
 
#------------------------------------------


sub isText() { not shift->isBinary }

#------------------------------------------


sub dispositionFilename(;$)
{   my $self = shift;
    my $raw;

    my $field;
    if($field = $self->disposition)
    {   $raw  = $field->attribute('filename')
             || $field->attribute('file')
             || $field->attribute('name');
    }

    if(!defined $raw && ($field = $self->type))
    {   $raw  = $field->attribute('filename')
             || $field->attribute('file')
             || $field->attribute('name');
    }

    return $raw unless @_;

    my $dir      = shift;
    my $filename = '';
    if(defined $raw)
    {   $filename = basename $raw;
        $filename =~ s/[^\w.-]//;
    }

    unless(length $filename)
    {   my $ext    = ($self->mimeType->extensions)[0] || 'raw';
        my $unique;
        for($unique = 'part-0'; 1; $unique++)
        {   my $out = File::Spec->catfile($dir, "$unique.$ext");
            open IN, "<", $out or last;  # does not exist: can use it
            close IN;
        }
        $filename = "$unique.$ext";
    }

    File::Spec->catfile($dir, $filename);
}

#------------------------------------------


my %transfer_encoder_classes =
 ( base64  => 'Mail::Message::TransferEnc::Base64'
 , binary  => 'Mail::Message::TransferEnc::Binary'
 , '8bit'  => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 , '7bit'  => 'Mail::Message::TransferEnc::SevenBit'
 );

my %transfer_encoders;   # they are reused.

sub getTransferEncHandler($)
{   my ($self, $type) = @_;

    return $transfer_encoders{$type}
        if exists $transfer_encoders{$type};   # they are reused.

    my $class = $transfer_encoder_classes{$type};
    return unless $class;

    eval "require $class";
    confess "Cannot load $class: $@\n" if $@;

    $transfer_encoders{$type} = $class->new;
}

#------------------------------------------


sub addTransferEncHandler($$)
{   my ($this, $name, $what) = @_;

    my $class;
    if(ref $what)
    {   $transfer_encoders{$name} = $what;
        $class = ref $what;
    }
    else
    {   delete $transfer_encoders{$name};
        $class = $what;
    }

    $transfer_encoder_classes{$name} = $class;
    $this;
}

1;
