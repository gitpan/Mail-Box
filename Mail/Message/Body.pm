use strict;
use warnings;

package Mail::Message::Body;
our $VERSION = 2.036;  # Part of Mail::Box
use base 'Mail::Reporter';

use Mail::Message::Field;
use Mail::Message::Body::Lines;
use Mail::Message::Body::File;

use Carp;
use Scalar::Util 'weaken';

use overload bool  => sub {1}   # $body->print if $body
           , '""'  => 'string_unless_carp'
           , '@{}' => 'lines'
           , '=='  => sub {$_[0]->{MMB_seqnr}==$_[1]->{MMB_seqnr}}
           , '!='  => sub {$_[0]->{MMB_seqnr}!=$_[1]->{MMB_seqnr}};

use MIME::Types;
my $mime_types = MIME::Types->new;

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

    $self->{MM_modified} = $args->{modified} || 0;

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
        {   $self->_data_from_lines( [split /^/, $data] ) }
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

    my ($mime, $transfer, $disp);
    if($args->{disposition}) {$disp = $args->{disposition} }
    elsif(defined $filename)
    {   $disp = Mail::Message::Field->new
          ( 'Content-Disposition' => (-T $filename ? 'inline' : 'attachment'));
        (my $abbrev = $filename) =~ s!.*[/\\]!!;
        $disp->attribute(filename => $abbrev);
    }

    if(defined $args->{mime_type}) {$mime = $args->{mime_type} }
    elsif(defined $filename)
    {   $mime = $mime_types->mimeTypeOf($filename);
        $mime = -T $filename ? 'text/plain' : 'application/octet-stream'
            unless defined $mime;
    }

    $mime = $mime->type if ref $mime && $mime->isa('MIME::Type');

    if(defined(my $based = $args->{based_on}))
    {   $mime     = $based->type        unless defined $mime;
        $transfer = $args->{transfer_encoding} || $based->transferEncoding;
        $disp     = $based->disposition unless defined $disp;

        $self->{MMB_checked} = defined $args->{checked}
           ? $args->{checked} : $based->checked;
    }
    else
    {   $transfer = $args->{transfer_encoding} || 'none';
        $disp     = 'none'              unless defined $disp;
        $self->{MMB_checked} = $args->{checked}|| 0;
    }

    $mime = 'text/plain' unless defined $mime;

    unless(ref $mime)
    {   $mime = Mail::Message::Field->new('Content-Type' => lc $mime);
        $mime->attribute(charset => $args->{charset} || 'us-ascii')
            if $mime =~ m!^text/!;
    }

    $transfer = Mail::Message::Field->new('Content-Transfer-Encoding' =>
        lc $transfer) unless ref $transfer;

    $disp     = Mail::Message::Field->new('Content-Disposition' => $disp)
        unless ref $disp;

    @$self{ qw/MMB_type MMB_transfer MMB_disposition/ }
        = ($mime, $transfer, $disp);
    $self->{MMB_eol}   = $args->{eol} || 'NATIVE';

    # Set message where the body belongs to.

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMB_seqnr} = $body_count++;
    $self;
}

sub clone() {shift->notImplemented}

sub message(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MMB_message} = shift;
        weaken($self->{MMB_message});
    }
    $self->{MMB_message};
}

sub modified(;$)
{  my $self = shift;
   @_? $self->{MM_modified} = shift : $self->{MM_modified};
}

sub print(;$) {shift->notImplemented}

sub isDelayed() {0}

sub isMultipart() {0}

sub isNested() {0}

sub decoded(@)
{   my $self = shift;
    $self->encode
     ( mime_type         => 'text/plain'
     , charset           => 'us-ascii'
     , transfer_encoding => 'none'
     , @_
     );
}

sub type() { shift->{MMB_type} }

sub mimeType()
{   my $self = shift;
    return $self->{MMB_mime} if exists $self->{MMB_mime};

    my $type = $self->{MMB_type}->body;

    $self->{MMB_mime}
       = $mime_types->type($type) || MIME::Type->new(type => $type);
}

sub charset() { shift->type->attribute('charset') }

sub transferEncoding(;$)
{   my $self = shift;
    return $self->{MMB_transfer} unless @_;

    my $set = shift;
    $self->{MMB_transfer} = ref $set ? $set
       : Mail::Message::Field->new('Content-Transfer-Encoding' => $set);
}

sub disposition(;$)
{   my $self = shift;

    if(@_)
    {   my $disp = shift;
        $self->{MMB_disposition} = ref $disp ? $disp
          : Mail::Message::Field->new('Content-Disposition' => $disp);
    }

    $self->{MMB_disposition};
}

sub checked(;$)
{   my $self = shift;
    @_ ? $self->{MMB_checked} = shift : $self->{MMB_checked};
}

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

sub nrLines(@)  {shift->notImplemented}

sub size(@)  {shift->notImplemented}

sub string() {shift->notImplemented}

sub string_unless_carp()
{   my $self  = shift;
    return $self->string unless (caller)[0] eq 'Carp';

    (my $class = ref $self) =~ s/^Mail::Message/MM/;
    "$class object";
}

sub lines() {shift->notImplemented}

sub file(;$) {shift->notImplemented}

my @in_encode = qw/check encode encoded eol isBinary isText unify/;
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

sub read(@) {shift->notImplemented}

sub fileLocation(;@) {
    my $self = shift;
    return @$self{ qw/MMB_begin MMB_end/ } unless @_;
    @$self{ qw/MMB_begin MMB_end/ } = @_;
}

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMB_begin} -= $dist;
    $self->{MMB_end}   -= $dist;
    $self;
}

sub load() {shift}

1;
