use strict;
use warnings;

package Mail::Message::Field;
our $VERSION = 2.025;  # Part of Mail::Box
use base 'Mail::Reporter';

use Carp;
use Mail::Address;
use Date::Parse;

our %_structured;  # not to be used directly: call isStructured!
my $default_wrap_length = 78;

use overload qq("") => sub { $_[0]->unfolded_body }
           , '+0'   => 'toInt'
           , bool   => sub {1}
           , cmp    => sub { $_[0]->unfolded_body cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;

sub new(@)
{   my $class = shift;
    if($class eq __PACKAGE__)  # bootstrap
    {   require Mail::Message::Field::Fast;
        return Mail::Message::Field::Fast->new(@_);
    }
    $class->SUPER::new(@_);
}

BEGIN {
%_structured = map { (lc($_) => 1) }
  qw/To Cc Bcc From Date Reply-To Sender
     Resent-Date Resent-From Resent-Sender Resent-To Return-Path
     List-Help List-Post List-Unsubscribe Mailing-List
     Received References Message-ID In-Reply-To
     Content-Length Content-Type
     Delivered-To
     Lines
     MIME-Version
     Precedence
     Status/;
}

sub isStructured(;$)
{   my $name  = ref $_[0] ? shift->name : $_[1];
    exists $_structured{lc $name};
}

sub wellformedName(;$)
{   my $thing = shift;
    my $name = @_ ? shift : $thing->name;
    $name =~ s/(\w+)/\L\u$1/g;
    $name;
}

sub body()
{   my $self = shift;
    my $body = $self->unfolded_body;
    return $body unless $self->isStructured;

    $body =~ s/\s*\;.*//s;
    $body;
}

sub comment(;$)
{   my $self = shift;
    return undef unless $self->isStructured;

    my $body = $self->unfolded_body;

    if(@_)
    {   my $comment = shift;
        $body    =~ s/\s*\;.*//;
        $body   .= "; $comment" if defined $comment && length $comment;
        $self->unfolded_body($body);
        return $comment;
    }

    $body =~ s/.*?\;\s*// ? $body : '';
}

sub content() { shift->unfolded_body }  # Compatibility

sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $body  = $self->unfolded_body;

    unless(@_)
    {   $body =~ m/\b$attr=( "( (?: [^"]|\\" )* )"
                           | '( (?: [^']|\\' )* )'
                           | (\S*)
                           )
                  /xi;
        return $+;
    }

    my $value = shift;
    unless(defined $value)  # remove attribute
    {   for($body)
        {      s/\b$attr='([^']|\\')*'//i
            or s/\b$attr="([^"]|\\")*"//i
            or s/\b$attr=\S*//i;
        }
        $self->unfolded_body($body);
        return undef;
    }

    (my $quoted = $value) =~ s/"/\\"/g;
    for($body)
    {       s/\b$attr='([^']|\\')*'/$attr="$quoted"/i
         or s/\b$attr="([^"]|\\")*"/$attr="$quoted"/i
         or s/\b$attr=\S+/$attr="$quoted"/i
         or do { $_ .= qq(; $attr="$quoted") }
    }

    $self->unfolded_body($body);
    $value;
}

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print($self->folded);
}

sub toString(;$)
{   my $self  = shift;
    return $self->folded unless @_;

    my $wrap  = shift || $default_wrap_length;
    my $name  = $self->Name;
    my @lines = $self->fold($name, $self->unfolded_body, $wrap);
    $lines[0] = $name . ':' . $lines[0];
    wantarray ? @lines : join('', @lines);
}

sub toInt()
{   my $self = shift;
    return $1 if $self->body =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not numerical: ". $self->toString);

    return undef;
}

sub toDate($)
{   my $class = shift;
    use POSIX 'strftime';
    my @time  = @_ ? localtime(shift) : localtime;
    strftime "%a, %d %b %Y %H:%M:%S %z", @time;
}

sub stripCFWS($)
{   my $thing  = shift;
    my $string = @_ ? shift : $thing->unfolded_body;

    for($string)
    {  s/(?: \(
                 ( [^()]*
                   \( [^()]* \)
                 )*
                 [^()]*
             \)
          )/ /gsx;
       s/\s+/ /gs;
       s/\s+$//;
       s/^\s+//;
    }
    $string;
}

sub dateToTimestamp($)
{   my $string = $_[0]->stripCFWS($_[1]);

    # in RFC822, FWSes can appear within the time.
    $string =~ s/(\d\d)\s*\:\s*(\d\d)\s*\:\s*(\d\d)/$1:$2:$3/;

    str2time($string, 'GMT');
}

sub addresses() { Mail::Address->parse(shift->body) }

sub nrLines() { my @l = shift->folded_body; scalar @l }

sub size() {length shift->toString}

sub toDisclose()
{   shift->name !~ m!^(?: (?:x-)?status
                      |   (?:resent-)?bcc
                      |   Content-Length
                      ) $!x;
}

sub consume($;$)
{   my $self = shift;
    my ($name, $body) = defined $_[1] ? @_ : split(/\s*\:\s*/, (shift), 2);

    Mail::Reporter->log(WARNING => "Illegal character in field name: $name")
       if $name =~ m/[^\041-\071\073-\176]/;

    #
    # Compose the body.
    #

    if(ref $body)                 # Objects
    {   my @objs = ref $body eq 'ARRAY' ? @$body
                 : defined $body        ? ($body)
                 :                        ();

        # Skip field when no objects are specified.
        return () unless @objs;

        # Format the addresses
        my @addrs = map {ref $_ && $_->isa('Mail::Address') ? $_->format : "$_"}             @objs;

        $body = $self->fold($name, join(', ', @addrs));
    }
    elsif($body !~ s/\n+$/\n/g)   # Added by user...
    {   $body = $self->fold($name, $body);
    }
    else                          # Created by parser
    {   # correct erroneous wrap-seperators (dos files under UNIX)
        $body =~ s/[\012\015]+/\n/g;
        $body = ' '.$body unless substr($body, 0, 1) eq ' ';

        if($body eq "\n")
        {   Mail::Reporter->log(WARNING => "Empty field: $name\n");
            return ();
        }
    }

    ($name, $body);
}

sub setWrapLength(;$)
{   my $self = shift;
    $self->[1] = $self->fold($self->[0],$self->unfolded_body, @_);
}

sub defaultWrapLength(;$)
{   my $self = shift;
    @_ ? ($default_wrap_length = shift) : $default_wrap_length;
}

sub fold($$;$)
{   my $self = shift;
    my $name = shift;
    my $line = shift;
    my $wrap = shift || $default_wrap_length;

    my @folded;
    while(1)
    {  my $max = $wrap - (@folded ? 1 : length($name) + 2);
       my $min = $max >> 2;
       last if length $line < $max;

          $line =~ s/^ ( .{$min,$max}   # $max to 30 chars
                        [;,]            # followed by a; or ,
                       )[ \t]           # and then a WSP
                    //x
       || $line =~ s/^ ( .{$min,$max} ) # $max to 30 chars
                       [ \t]            # followed by a WSP
                    //x
       || $line =~ s/^ ( .{$max,}? )    # longer, but minimal chars
                       [ \t]            # followed by a WSP
                    //x
       || $line =~ s/^ (.*) //x;        # everything

       push @folded, " $1\n";
    }

    push @folded, " $line\n";
    wantarray ? @folded : join('', @folded);
}

sub unfold($)
{   my $string = $_[1];
    for($string)
    {   s/\n//g;
        s/^ //;
    }
    $string;
}

1;
