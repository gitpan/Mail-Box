use strict;
use warnings;

package Mail::Message::Field::URIs;
use vars '$VERSION';
$VERSION = '2.054';
use base 'Mail::Message::Field::Structured';
use Carp 'confess';

use URI;



sub init($)
{   my ($self, $args) = @_;

    my ($body, @body);
    if($body = delete $args->{body})
    {   @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
    }

    $self->{MMFU_uris} = [];

    if(@body > 1 || ref $body[0])
    {   $self->addURI($_) foreach @body;
    }
    elsif(defined $body)
    {   $body = "<$body>\n" unless index($body, '<') >= 0;
        $args->{body} = $body;
    }

    $self->SUPER::init($args);
}

#------------------------------------------

sub parse($)
{   my ($self, $string) = @_;
    my @raw = $string =~ m/\<([^>]+)\>/g;  # simply ignore all but <>
    $self->addURI($_) foreach @raw;
    $self;
}

#------------------------------------------

sub produceBody()
{  my @uris = sort map { $_->as_string } shift->URIs;
   local $" = '>, <';
   @uris ? "<@uris>" : undef;
}

#------------------------------------------


sub addURI(@)
{   my $self  = shift;
    my $uri   = ref $_[0] ? shift : URI->new(@_);
    push @{$self->{MMFU_uris}}, $uri->canonical if defined $uri;
    $uri;
}

#------------------------------------------


sub URIs() { @{shift->{MMFU_uris}} }

#------------------------------------------


sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for URI fields.');
    $self;
}

#------------------------------------------


sub addExtra($@)
{   my $self = shift;
    $self->log(ERROR => 'No extras in URI fields.');
    $self;
}

#------------------------------------------


1;
