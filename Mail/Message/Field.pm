use strict;
use warnings;

# This package defines the only object in Mail::Box which is not
# derived from Mail::Reporter.  See the manual page.

package Mail::Message::Field;
our $VERSION = 2.021;  # Part of Mail::Box
use Mail::Box::Parser;

use Carp;
use Mail::Address;

our %_structured;  # not to be used directly: call isStructured!

use overload qq("") => sub { $_[0]->body }
           , '+0'   => 'toInt'
           , bool   => sub {1}
           , cmp    => sub { $_[0]->body cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;

sub new(@)
{   shift;
    require Mail::Message::Field::Fast;
    Mail::Message::Field::Fast->new(@_);
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

sub content()
{   my $self    = shift;
    my $comment = $self->comment;
    $self->body . ($comment ? "; $comment" : '');
}

sub attribute($;$)
{   my ($self, $name) = (shift, shift);

    if(@_ && defined $_[0])
    {   my $value   = shift;
        my $comment = $self->comment;
        if(defined $comment)
        {      if($comment =~ s/\b$name='[^']*'/$name='$value'/i) {;}
            elsif($comment =~ s/\b$name="[^"]*"/$name="$value"/i) {;}
            elsif($comment =~ s/\b$name=\S+/$name="$value"/i)     {;}
            else {$comment .= qq(; $name="$value") }
        }
        else { $comment = qq($name="$value") }

        $self->comment($comment);
        $self->setWrapLength(72);
        return $value;
    }

    my $comment = $self->comment or return;
    $comment =~ m/\b$name=('([^']*)'|"([^"]*)"|(\S*))/i ;
    $+;
}

sub print($)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print($self->folded);
}

sub toString()
{   my @folded = shift->folded;
    wantarray ? @folded : join('', @folded);
}

sub toInt()
{   my $self = shift;
    return $1 if $self->body =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not numerical: ". $self->toString);

    return undef;
}

sub toDate($)
{   my ($class, @time) = @_;
    use POSIX 'strftime';
    strftime "%a, %d %b %Y %H:%M:%S %z", @time;
}

sub addresses() { Mail::Address->parse(shift->body) }

sub nrLines() { my @l = shift->folded; scalar @l }

sub size() {length shift->toString}

sub setWrapLength($)
{   my $self = shift;
    return $self unless $self->isStructured;

    my $wrap = shift;
    my $line = $self->toString;

    $self->folded
      ( length $line < $wrap ? undef
      : Mail::Box::Parser->defaultParserType->foldHeaderLine($line, $wrap)
      );

    $self;
}

1;
