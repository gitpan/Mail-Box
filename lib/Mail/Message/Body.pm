use strict;
use warnings;

package Mail::Message::Body;
use vars '$VERSION';
$VERSION = '2.053';
use base 'Mail::Reporter';

use Mail::Message::Field;
use Mail::Message::Body::Lines;
use Mail::Message::Body::File;

use Carp;
use Scalar::Util 'weaken';

use MIME::Types;
my $mime_types = MIME::Types->new;
my $mime_plain = $mime_types->type('text/plain');


use overload bool  => sub {1}   # $body->print if $body
           , '""'  => 'string_unless_carp'
           , '@{}' => 'lines'
           , '=='  => sub {$_[0]->{MMB_seqnr}==$_[1]->{MMB_seqnr}}
           , '!='  => sub {$_[0]->{MMB_seqnr}!=$_[1]->{MMB_seqnr}};

#------------------------------------------


my $body_count = 0;  # to be able to compare bodies for equivalence.

sub new(@)
{   my $class = shift;

    return $class->SUPER::new(@_)
         unless $class eq __PACKAGE__;

    my %args  = @_;

      exists $args{file}
    ? Mail::Message::Body::File->new(@_)
    : Mail::Message::Body::Lines->new(@_);
}

# All body implementations shall implement all of the following!!

sub _data_from_filename(@)   {shift->notImplemented}
sub _data_from_filehandle(@) {shift->notImplemented}
sub _data_from_glob(@)       {shift->notImplemented}
sub _data_from_lines(@)      {shift->notImplemented}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMB_modified} = $args->{modified} || 0;

    my $filename;
    if(defined(my $file = $args->{file}))
    {
        if(!ref $file)
        {    $self->_data_from_filename($file) or return;
             $filename = $file;
        }
        elsif(ref $file eq 'GLOB')
        {    $self->_data_from_glob($file) or return }
        elsif($file->isa('IO::Handle'))
        {    $self->_data_from_filehandle($file) or return }
        else
        {    croak "Illegal datatype for file option." }
    }
    elsif(defined(my $data = $args->{data}))
    {
        if(!ref $data)
        {   my @lines = split /^/, $data;
            $lines[-1] .= "\n" if @lines && substr($lines[-1], -1) ne "\n";
            $self->_data_from_lines(\@lines)
        }
        elsif(ref $data eq 'ARRAY')
        {   $self->_data_from_lines($data) or return }
        else
        {   croak "Illegal datatype for data option." }
    }
    elsif(! $self->isMultipart && ! $self->isNested)
    {   # Neither 'file' nor 'data', so empty body.
        $self->_data_from_lines( [] ) or return;
    }

    # Set the content info

    my ($mime, $transfer, $disp)
      = @$args{ qw/mime_type transfer_encoding disposition/ };

    if(defined $filename)
    {   unless(defined $disp)
        {   $disp = Mail::Message::Field->new
              ('Content-Disposition' => (-T $filename ? 'inline':'attachment'));
            (my $abbrev = $filename) =~ s!.*[/\\]!!;
            $disp->attribute(filename => $abbrev);
        }

        unless(defined $mime)
        {   $mime = $mime_types->mimeTypeOf($filename);
            $mime = -T $filename ? 'text/plain' : 'application/octet-stream'
                unless defined $mime;
        }
    }

    $mime = $mime->type if ref $mime && $mime->isa('MIME::Type');

    if(defined(my $based = $args->{based_on}))
    {   $mime     = $based->type             unless defined $mime;
        $transfer = $based->transferEncoding unless defined $transfer;
        $disp     = $based->disposition      unless defined $disp;

        $self->{MMB_checked}
               = defined $args->{checked} ? $args->{checked} : $based->checked;
    }
    else
    {   $transfer = $args->{transfer_encoding};
        $self->{MMB_checked} = $args->{checked}|| 0;
    }

    if(defined $mime)
    {   $mime = $self->type($mime);
        $mime->attribute(charset => $args->{charset} || 'us-ascii')
            if $mime =~ m!^text/!;
    }

    $self->transferEncoding($transfer) if defined $transfer;
    $self->disposition($disp)          if defined $disp;

    $self->{MMB_eol}   = $args->{eol} || 'NATIVE';

    # Set message where the body belongs to.

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMB_seqnr} = $body_count++;
    $self;
}

#------------------------------------------


sub clone() {shift->notImplemented}

#------------------------------------------


sub decoded(@)
{   my $self = shift;
    $self->encode
     ( mime_type         => 'text/plain'
     , charset           => 'us-ascii'
     , transfer_encoding => 'none'
     , @_
     );
}

#------------------------------------------


sub eol(;$)
{   my $self = shift;
    return $self->{MMB_eol} unless @_;

    my $eol  = shift;
    if($eol eq 'NATIVE')
    {   $eol = $^O =~ m/^win/i ? 'CRLF'
             : $^O =~ m/^mac/i ? 'CR'
             :                   'LF';
    }

    return $eol if $eol eq $self->{MMB_eol} && $self->checked;
    my $lines = $self->lines;

       if($eol eq 'CR')    {s/[\015\012]+$/\015/     foreach @$lines}
    elsif($eol eq 'LF')    {s/[\015\012]+$/\012/     foreach @$lines}
    elsif($eol eq 'CRLF')  {s/[\015\012]+$/\015\012/ foreach @$lines}
    else
    {   carp "Unknown line terminator $eol ignored.";
        return $self->eol('NATIVE');
    }

    (ref $self)->new
      ( based_on => $self
      , eol      => $eol
      , data     => $lines
      );
}

#------------------------------------------


sub message(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MMB_message} = shift;
        weaken($self->{MMB_message});
    }
    $self->{MMB_message};
}

#------------------------------------------


sub isDelayed() {0}

#------------------------------------------


sub isMultipart() {0}

#------------------------------------------


sub isNested() {0}

#------------------------------------------


sub type(;$)
{   my $self = shift;
    return $self->{MMB_type} if !@_ && defined $self->{MMB_type};

    delete $self->{MMB_mime};
    my $type = defined $_[0] ? shift : 'text/plain';

    $self->{MMB_type}
      = ref $type ? $type->clone
      : Mail::Message::Field->new('Content-Type' => $type);
}

#------------------------------------------


sub mimeType()
{   my $self  = shift;
    return $self->{MMB_mime} if exists $self->{MMB_mime};

    my $field = $self->{MMB_type};
    my $body  = defined $field ? $field->body : '';

    return $self->{MMB_mime} = $mime_plain
       unless length $body;

    $self->{MMB_mime}
       = $mime_types->type($body) || MIME::Type->new(type => $body);
}

#------------------------------------------


sub charset() { shift->type->attribute('charset') }

#------------------------------------------


sub transferEncoding(;$)
{   my $self = shift;
    return $self->{MMB_transfer} if !@_ && defined $self->{MMB_transfer};

    my $set = defined $_[0] ? shift : 'none';
    $self->{MMB_transfer} = ref $set ? $set->clone
       : Mail::Message::Field->new('Content-Transfer-Encoding' => $set);
}

#------------------------------------------


sub disposition(;$)
{   my $self = shift;
    return $self->{MMB_disposition} if !@_ && $self->{MMB_disposition};

    my $disp = defined $_[0] ? shift : 'none';
    $self->{MMB_disposition} = ref $disp ? $disp->clone
       : Mail::Message::Field->new('Content-Disposition' => $disp);
}

#------------------------------------------


sub checked(;$)
{   my $self = shift;
    @_ ? ($self->{MMB_checked} = shift) : $self->{MMB_checked};
}

#------------------------------------------


sub nrLines(@)  {shift->notImplemented}

#------------------------------------------


sub size(@)  {shift->notImplemented}

#------------------------------------------


sub string() {shift->notImplemented}

sub string_unless_carp()
{   my $self  = shift;
    return $self->string unless (caller)[0] eq 'Carp';

    (my $class = ref $self) =~ s/^Mail::Message/MM/;
    "$class object";
}

#------------------------------------------


sub lines() {shift->notImplemented}

#------------------------------------------


sub file(;$) {shift->notImplemented}

#------------------------------------------


sub print(;$) {shift->notImplemented}

#------------------------------------------


sub printEscapedFrom($) {shift->notImplemented}

#------------------------------------------


sub write(@)
{   my ($self, %args) = @_;
    my $filename = $args{filename};
    die "No filename for write() body" unless defined $filename;

    open OUT, '>', $filename or return;
    $self->print(\*OUT);
    close OUT or return undef;
    $self;
}

#------------------------------------------


sub read(@) {shift->notImplemented}

#------------------------------------------


sub contentInfoTo($)
{   my ($self, $head) = @_;
    return unless defined $head;

    my $lines  = $self->nrLines;
    my $size   = $self->size;
    $size     += $lines if $Mail::Message::crlf_platform;

    $head->set($self->type);
    $head->set('Content-Length' => $size);
    $head->set(Lines            => $lines);

    $head->set($self->transferEncoding);
    $head->set($self->disposition);
    $self;
}

#------------------------------------------


sub contentInfoFrom($)
{   my ($self, $head) = @_;

    $self->type($head->get('Content-Type'));
    $self->transferEncoding($head->get('Content-Transfer-Encoding'));
    $self->disposition($head->get('Content-Disposition'));

    delete $self->{MMB_mime};
    $self;

}
#------------------------------------------


sub modified(;$)
{  my $self = shift;
   return $self->isModified unless @_;  # compat 2.036
   $self->{MMB_modified} = shift;
}

#------------------------------------------


sub isModified() {  shift->{MMB_modified} }

#------------------------------------------


sub fileLocation(;@) {
    my $self = shift;
    return @$self{ qw/MMB_begin MMB_end/ } unless @_;
    @$self{ qw/MMB_begin MMB_end/ } = @_;
}

#------------------------------------------


sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMB_begin} -= $dist;
    $self->{MMB_end}   -= $dist;
    $self;
}

#------------------------------------------


sub load() {shift}

#------------------------------------------


my @in_encode = qw/check encode encoded eol isBinary isText unify
                   dispositionFilename/;
my %in_module = map { ($_ => 'encode') } @in_encode;

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;

    my $mod = $in_module{$call} || 'construct';
    if($mod eq 'encode'){ require Mail::Message::Body::Encode    }
    else                { require Mail::Message::Body::Construct }

    no strict 'refs';
    return $self->$call(@_) if $self->can($call);  # now loaded

    # Try parental AUTOLOAD
    Mail::Reporter->$call(@_);
}   

#------------------------------------------


1;