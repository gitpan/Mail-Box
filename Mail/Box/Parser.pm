use strict;
use warnings;

package Mail::Box::Parser;
our $VERSION = 2.021;  # Part of Mail::Box
use base 'Mail::Reporter';
use Carp;

sub new(@)
{   my $class       = shift;

    return $class->defaultParserType->new(@_)   # bootstrap right parser
        if $class eq __PACKAGE__;

    my $self = $class->SUPER::new(@_) or return;
    $self->start;     # new includes init.
}

sub init(@)
{   my ($self, $args) = @_;

    $args->{trace} ||= 'WARNING';

    $self->SUPER::init($args);

    $self->{MBP_separator} = $args->{separator} || '';
    $self->{MBP_mode}      = $args->{mode}      || 'r';

    my $filename =
    $self->{MBP_filename}  = $args->{filename}
        or confess "Filename obligatory to create a parser.";

    $self->takeFileInfo;
    $self->log(NOTICE => "Created parser for $filename");

    $self;
}

my $parser_type;

sub defaultParserType(;$)
{   my $class = shift;

    # Select the parser manually?
    if(@_)
    {   $parser_type = shift;
        return $parser_type if $parser_type->isa( __PACKAGE__ );

        confess "Parser $parser_type does not extend "
              . __PACKAGE__ . "\n";
    }

    # Already determined which parser we want?
    return $parser_type if $parser_type;

    # Try to use C-based parser.
   eval 'require Mail::Box::Parser::C';
#warn "C-PARSER errors $@\n" if $@;
#   return $parser_type = 'Mail::Box::Parser::C'
#       unless $@;

    # Fall-back on Perl-based parser.
    require Mail::Box::Parser::Perl;
    $parser_type = 'Mail::Box::Parser::Perl';
}

sub start(@)
{   my ($self, %args) = @_;

    my $filename = $self->filename;

    unless($args{trust_file})
    {   if($self->fileChanged)
        {   $self->log(ERROR => "File $filename changed, refuse to continue.");
            return;
        }
    }

    $self->log(NOTICE => "Open file $filename to be parsed");
    $self;
}

sub stop()
{   my $self     = shift;
    my $filename = $self->filename;

    $self->log(WARNING => "File $filename changed during access.")
       if $self->fileChanged;

    $self->log(NOTICE => "Close parser for file $filename");
    $self;
}

sub takeFileInfo()
{   my $self     = shift;
    my $filename = $self->filename;
    @$self{ qw/MBP_size MBP_mtime/ } = (stat $filename)[7,9];
}

sub fileChanged()
{   my $self = shift;
    my $filename       = $self->filename;
    my ($size, $mtime) = (stat $filename)[7,9];
    return 0 unless $size;

      $size != $self->{MBP_size} ? 0
    : !defined $mtime            ? 1
    : $mtime != $self->{MBP_mtime};
}

sub filename() {shift->{MBP_filename}}

sub filePosition(;$) {shift->NotImplemented}

sub pushSeparator($) {shift->notImplemented}

sub popSeparator($) {shift->notImplemented}

sub readSeparator($) {shift->notImplemented}

sub readHeader()    {shift->notImplemented}

sub bodyAsString() {shift->notImplemented}

sub bodyAsList() {shift->notImplemented}

sub bodyAsFile() {shift->notImplemented}

sub bodyDelayed() {shift->notImplemented}

sub lineSeparator() {shift->{MBP_linesep}}

sub foldHeaderLine($$) {shift->notImplemented}

sub DESTROY
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->stop;
}

1;
