package Mail::Box::Search::SpamAssassin;
our $VERSION = 2.025;  # Part of Mail::Box
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

sub init($)
{   my ($self, $args) = @_;

    $args->{in}    ||= 'MESSAGE';
    $args->{found} ||= 'spam';

    $self->SUPER::init($args);

    my $found = $args->{found};
    $self->{MBSS_action}
       = ref $found         ? $found
       : $found eq 'DELETE' ? sub { $_[0]->delete }
       :                      sub { $_[0]->label($found => 1) };

    $self;
}

sub search(@)
{   my ($self, $object, %args) = @_;
    $self->SUPER::search($object, %args);
}

sub inHead(@)
{   my ($self, $part, $head, $args) = @_;

    0;
}

sub inBody(@)
{   my ($self, $part, $body, $args) = @_;

    my @details = (message => $part->toplevel, part => $part);
    my ($field_check, $match_check, $deliver)
      = @$self{ qw/MBSG_field_check MBSG_match_check MBSG_deliver/ };

    my $matched = 0;
    my $linenr  = 0;

  LINES:
    foreach my $line ($body->lines)
    {   $linenr++;
        next unless $match_check->($body, $line);

        $matched++;
        last LINES unless $deliver;  # no deliver: only one match needed
        $deliver->( {@details, linenr => $linenr, line => $line} );
    }

    $matched;
}

1;
