use strict;
package Mail::Box::Tie::ARRAY;
our $VERSION = 2.024;  # Part of Mail::Box

use Carp;

sub TIEARRAY(@)
{   my ($class, $folder) = @_;
    croak "No folder specified to tie to."
        unless ref $folder && $folder->isa('Mail::Box');

    bless { MBT_folder => $folder }, $class;
}

sub FETCH($)
{   my ($self, $index) = @_;
    my $msg = $self->{MBT_folder}->message($index);
    $msg->deleted ? undef : $msg;
}

sub STORE($$)
{   my ($self, $index, $msg) = @_;
    my $folder = $self->{MBT_folder};

    croak "Cannot simply replace messages in a folder: use delete old, then push new."
        if $index != $folder->messages;

    $folder->addMessages($msg);
    $msg;
}

sub FETCHSIZE()  { scalar shift->{MBT_folder}->messages }

sub PUSH(@)
{   my $folder = shift->{MBT_folder};
    $folder->addMessages(@_);
    scalar $folder->messages;
}

sub DELETE($) { shift->{MBT_folder}->message(shift)->delete }

sub STORESIZE($)
{   my $folder = shift->{MBT_folder};
    my $length = shift;
    $folder->message($_) foreach $length..$folder->messages;
    $length;
}

# DESTROY is implemented in Mail::Box

1;
