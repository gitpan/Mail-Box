use strict;
use warnings;

package Mail::Message::Field::Addresses;
our $VERSION = 2.039;  # Part of Mail::Box
use base 'Mail::Message::Field::Full';

use Mail::Message::Field::AddrGroup;
use Mail::Message::Field::Address;
use List::Util 'first';

# what is permitted for each field.

my $address_list = {groups => 1, multi => 1};
my $mailbox_list = {multi => 1};
my $mailbox      = {};

my %accepted     =
 ( from       => $mailbox_list
 , sender     => $mailbox
 , 'reply-to' => $address_list
 , to         => $address_list
 , cc         => $address_list
 , bcc        => $address_list
 );

sub init($)
{   my ($self, $args) = @_;

    $self->{is_structured} = 1;

    my $name = $args->{name};
    if(my $body = $args->{body})
    {   my @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
#       $args->{body} = $self->encode(join(", ", @body), %$args);
    }
    else
    {   ($name, my $body) = split /\s*\:/, $name, 2;
        $args->{name} = $name;
        return () unless defined $body;
#       $args->{body} = $body;
    }

    $self->SUPER::init($args) or return;

    (my $def = lc $name) =~ s/^resent\-//;
    $self->{MMFF_defaults} = $accepted{$def} || {};
    $self->{MMFF_groups}   = [];

    $self;
}

sub parse($)
{   my ($self, $string) = @_;
    my ($group, $comment);

    while(1)
    {   ($comment, $string) = $self->consumeComment($string);

        if($string =~ s/^\s*\;// ) { undef $group; next }  # end group
        if($string =~ s/^\s*\,// ) { next }                # end address

        (my $phrase, $string) = $self->consumePhrase($string);
        if(defined $phrase)
        {   ($comment, $string) = $self->consumeComment($string);
            if($string =~ s/\s*\:// ) { $group = $phrase; next }

            if($string =~ s/\@// )
            {   (my $domain, $string, my $domcomment)
                   = $self->consumeDomain($string);
                ($comment, $string) = $self->consumeComment($string);

                $self->addAddress(local => $phrase, group => $group
                   , comment => $comment, domcomment => $domcomment);

                next;
            }
        }

        if($string =~ s/^\s*\<([^>]*)\>//)
        {   # remove obsoleted route info.
            (my $angle = $1) =~ s/^\@.*?\://;

            my $email = $self->consumeAddress($angle);
            $email->name($phrase)     if defined $phrase;
            $email->comment($comment) if defined $comment;

            ($comment, $string) = $self->consumeComment($string);
            $email->comment($comment) if defined $comment;

            $self->addAddress($email);
        }

        return 1 if m/^\s*$/;

        $self->log(WARNING => 'Illegal part in address field '.$self->Name.
                    ": $string\n");
        return 0;
    }
}

sub addAddress(@)
{   my $self  = shift;
    my $email = @_ && ref $_[0] ? shift : undef;
    my %args  = @_;
    my $group = delete $args{group};

    $email = Mail::Message::Field::Address->new(%args)
        unless defined $email;

    my $set = $self->group($group) || $self->addGroup(name => $group);
    $set->addAddress($email);
}

sub addGroup(@)
{   my $self  = shift;

    my $group = @_ == 1 ? shift
              : Mail::Message::Field::AddrGroup->new(@_);

    push @{$self->{MMFF_groups}}, $group;
    $group;
}

sub group($)
{   my ($self, $name) = @_;
    $name = '' unless defined $name;
    first { lc($_->name) eq lc($name) } $self->groups;
}

sub groups() { @{shift->{MMFF_groups}} }

sub groupNames() { map {$_->name} shift->groups }

sub addresses() { map {$_->addresses} shift->groups }

sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for address fields.');
    $self;
}

sub addExtra($@)
{   my $self = shift;
    $self->log(ERROR => 'No extras in address fields.');
    $self;
}

sub consumeAddress($)
{   my ($self, $string) = @_;

    (my $local, $string, my $comment) = $self->consumeDotAtom($string);
    $local =~ s/\s//g;

    return (undef, $_[0])
        unless defined $local && $string =~ s/^\s*\@//;

    (my $domain, $string, my $domcomment) = $self->consumeDomain($string);
    return (undef, $_[0]) unless defined $domain;

    my $email   = Mail::Message::Field::Address->new
     ( local => $local, domain => $domain, comment => $comment
     , domcomment => $domcomment );

    ($email, $string);
}

sub consumeDomain($)
{   my ($self, $string) = @_;

    return ($self->stripCFWS($1), $string)
        if $string =~ s/\s*(\[(?:[^[]\\]*|\\.)*\])//;

    my ($atom, $rest, $comment) = $self->consumeDotAtom($string);
    $atom =~ s/\s//g;
    ($atom, $rest, $comment);
}

1;
