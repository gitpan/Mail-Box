use strict;
use warnings;

package Mail::Message::Field;
use vars '$VERSION';
$VERSION = '2.042';
use base 'Mail::Reporter';

use Carp;
use Mail::Address;
use Date::Parse;

our %_structured;  # not to be used directly: call isStructured!
my $default_wrap_length = 78;


use overload qq("") => sub { $_[0]->unfoldedBody }
           , '+0'   => sub { $_[0]->toInt || 0 }
           , bool   => sub {1}
           , cmp    => sub { $_[0]->unfoldedBody cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;

#------------------------------------------


sub new(@)
{   my $class = shift;
    if($class eq __PACKAGE__)  # bootstrap
    {   require Mail::Message::Field::Fast;
        return Mail::Message::Field::Fast->new(@_);
    }
    $class->SUPER::new(@_);
}

#------------------------------------------


#------------------------------------------


#------------------------------------------


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

#------------------------------------------


sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print(scalar $self->folded);
}

#------------------------------------------


sub toString(;$) {my $self = shift;$self->string(@_)}
sub string(;$)
{   my $self  = shift;
    return $self->folded unless @_;

    my $wrap  = shift || $default_wrap_length;
    my $name  = $self->Name;
    my @lines = $self->fold($name, $self->unfoldedBody, $wrap);
    $lines[0] = $name . ':' . $lines[0];
    wantarray ? @lines : join('', @lines);
}

#------------------------------------------


sub toDisclose()
{   shift->name !~ m!^(?: (?:x-)?status
                      |   (?:resent-)?bcc
                      |   Content-Length
                      |   x-spam-
                      ) $!x;
}

#------------------------------------------


sub nrLines() { my @l = shift->foldedBody; scalar @l }

#------------------------------------------


sub size() {length shift->toString}

#------------------------------------------


# attempt to change the case of a tag to that required by RFC822. That
# being all characters are lowercase except the first of each
# word. Also if the word is an `acronym' then all characters are
# uppercase. We, rather arbitrarily, decide that a word is an acronym
# if it does not contain a vowel and isn't the well-known 'Cc' or
# 'Bcc' headers.

my %wf_lookup
  = qw/mime MIME  ldap LDAP  soap SOAP
       bcc Bcc  cc Cc/;

sub wellformedName(;$)
{   my $thing = shift;
    my $name = @_ ? shift : $thing->name;

    join '-',
       map { $wf_lookup{lc $_} || ( /[aeiouyAEIOUY]/ ? ucfirst lc : uc ) }
          split /\-/, $name;
}

#------------------------------------------


#------------------------------------------


sub body()
{   my $self = shift;
    my $body = $self->unfoldedBody;
    return $body unless $self->isStructured;

    $body =~ s/\s*\;.*//s;
    $body;
}

#------------------------------------------


#------------------------------------------


#------------------------------------------


sub stripCFWS($)
{   my $thing  = shift;

    # get (folded) data
    my $string = @_ ? shift : $thing->foldedBody;

    # remove comments
    my $r          = '';
    my $in_dquotes = 0;
    my $open_paren = 0;

    my @s = split m/([()"])/, $string;
    while(@s)
    {   my $s = shift @s;

           if(length $r && substr($r, -1) eq "\\") { $r .= $s } # esc'd special
        elsif($s eq '"')   { $in_dquotes = not $in_dquotes; $r .= $s }
        elsif($s eq '(' && !$in_dquotes) { $open_paren++ }
        elsif($s eq ')' && !$in_dquotes) { $open_paren-- }
        elsif($open_paren) {}  # in comment
        else               { $r .= $s }
    }

    # beautify and unfold at the same time
    for($r)
    {  s/\s+/ /gs;
       s/\s+$//;
       s/^\s+//;
    }

    $r;
}

#------------------------------------------


sub comment(;$)
{   my $self = shift;
    return undef unless $self->isStructured;

    my $body = $self->unfoldedBody;

    if(@_)
    {   my $comment = shift;
        $body    =~ s/\s*\;.*//;
        $body   .= "; $comment" if defined $comment && length $comment;
        $self->unfoldedBody($body);
        return $comment;
    }
 
    $body =~ s/.*?\;\s*// ? $body : '';
}

#------------------------------------------

sub content() { shift->unfoldedBody }  # Compatibility

#------------------------------------------


sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $body  = $self->unfoldedBody;

    unless(@_)
    {   return
           $body =~ m/\b$attr\s*\=\s*
                       ( "( (?: [^"]|\\" )* )"
                       | '( (?: [^']|\\' )* )'
                       | (\S*)
                       )
                  /xi ? $+ : undef;
    }

    my $value = shift;
    unless(defined $value)  # remove attribute
    {   for($body)
        {      s/\b$attr\s*=\s*'([^']|\\')*'//i
            or s/\b$attr\s*=\s*"([^"]|\\")*"//i
            or s/\b$attr\s*=\s*\S*//i;
        }
        $self->unfoldedBody($body);
        return undef;
    }

    (my $quoted = $value) =~ s/"/\\"/g;
    for($body)
    {       s/\b$attr\s*=\s*'([^']|\\')*'/$attr="$quoted"/i
         or s/\b$attr\s*=\s*"([^"]|\\")*"/$attr="$quoted"/i
         or s/\b$attr\s*=\s*\S+/$attr="$quoted"/i
         or do { $_ .= qq(; $attr="$quoted") }
    }

    $self->unfoldedBody($body);
    $value;
}

#------------------------------------------


sub toInt()
{   my $self = shift;
    return $1 if $self->body =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not numerical: ". $self->toString);

    return undef;
}

#------------------------------------------


my @weekday = qw/Sun Mon Tue Wed Thu Fri Sat Sun/;
my @month   = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

sub toDate(@)
{   my $class = shift;
    use POSIX 'strftime';
    my @time  = @_== 0 ? localtime() : @_==1 ? localtime(shift) : @_;
    strftime "$weekday[$time[6]], %d $month[$time[4]] %Y %H:%M:%S %z", @time;
}

#------------------------------------------


sub addresses() { Mail::Address->parse(shift->unfoldedBody) }

#------------------------------------------


sub dateToTimestamp($)
{   my $string = $_[0]->stripCFWS($_[1]);

    # in RFC822, FWSes can appear within the time.
    $string =~ s/(\d\d)\s*\:\s*(\d\d)\s*\:\s*(\d\d)/$1:$2:$3/;

    str2time($string, 'GMT');
}


#------------------------------------------


#=notice Empty field: $name
#Empty fields are not allowed, however sometimes found in messages constructed
#by broken applications.  You probably want to ignore this message unless you
#wrote this broken application yourself.

sub consume($;$)
{   my $self = shift;
    my ($name, $body) = defined $_[1] ? @_ : split(/\s*\:\s*/, (shift), 2);

    Mail::Reporter->log(WARNING => "Illegal character in field name $name")
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
        my @strings = map {ref $_ && $_->isa('Mail::Address') ? $_->format : "$_"}
             @objs;

        my $text  = join(', ', @strings);
        $text     =~ s/\s+/ /g;
        $body = $self->fold($name, $text);
    }
    elsif($body !~ s/\n+$/\n/g)   # Added by user...
    {   $body = $self->fold($name, $body);
    }
    else                          # Created by parser
    {   # correct erroneous wrap-seperators (dos files under UNIX)
        $body =~ s/[\012\015]+/\n/g;
        $body =~ s/^[ \t]*/ /;  # start with one blank, folding kept unchanged

        $self->log(NOTICE => "Empty field: $name\n")
           if $body eq " \n";
    }

    ($name, $body);
}

#------------------------------------------


sub setWrapLength(;$)
{   my $self = shift;

    $self->[1] = $self->fold($self->[0],$self->unfoldedBody, @_)
        if @_ || $self->[1] !~ m/\n$/;

    $self;
}

#------------------------------------------


sub defaultWrapLength(;$)
{   my $self = shift;
    @_ ? ($default_wrap_length = shift) : $default_wrap_length;
}

#------------------------------------------


sub fold($$;$)
{   my $self = shift;
    my $name = shift;
    my $line = shift;
    my $wrap = shift || $default_wrap_length;

    $line    =~ s/\n\s/ /gms;            # Remove accidental folding
    return " \n" unless length $line;    # empty field

    my @folded;
    while(1)
    {  my $max = $wrap - (@folded ? 1 : length($name) + 2);
       my $min = $max >> 2;
       last if length $line < $max;

          $line =~ s/^ ( .{$min,$max}   # $max to 30 chars
                        [;,]            # followed at a ; or ,
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

    push @folded, " $line\n" if length $line;
    wantarray ? @folded : join('', @folded);
}

#------------------------------------------


sub unfold($)
{   my $string = $_[1];
    for($string)
    {   s/\n//g;
        s/^ +//;
    }
    $string;
}

#------------------------------------------


1;
