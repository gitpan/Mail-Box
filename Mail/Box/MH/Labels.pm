use strict;

package Mail::Box::MH::Labels;
our $VERSION = 2.027;  # Part of Mail::Box
use base 'Mail::Reporter';

use Mail::Message::Head::Subset;

use FileHandle;
use File::Copy;
use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{MBML_filename}  = $args->{filename}
       or croak "No label filename specified.";

    $self;
}

sub filename() {shift->{MBML_filename}}

sub get($)
{   my ($self, $msgnr) = @_;
    $self->{MBML_labels}[$msgnr];
}

sub read()
{   my $self = shift;
    my $seq  = $self->filename;

    open SEQ, '<', $seq
       or return;

    my @labels;

    local $_;
    while(<SEQ>)
    {   s/\s*\#.*$//;
        next unless length;

        next unless s/^\s*(\w+)\s*\:\s*//;
        my $label = $1;

        my $set   = 1;
           if($label eq 'cur'   ) { $label = 'current' }
        elsif($label eq 'unseen') { $label = 'seen'; $set = 0 }

        foreach (split /\s+/)
        {   if( /^(\d+)\-(\d+)\s*$/ )
            {   push @{$labels[$_]}, $label, $set foreach $1..$2;
            }
            elsif( /^\d+\s*$/ )
            {   push @{$labels[$_]}, $label, $set;
            }
        }
    }

    close SEQ;

    $self->{MBML_labels} = \@labels;
    $self;
}

sub write(@)
{   my $self     = shift;
    my $filename = $self->filename;

    # Remove when no messages are left.
    unless(@_)
    {   unlink $filename;
        return $self;
    }

    my $out      = FileHandle->new($filename, 'w') or return;
    $self->print($out, @_);
    $out->close;
    $self;
}

sub append(@)
{   my $self     = shift;
    my $filename = $self->filename;

    my $out      = FileHandle->new($filename, 'a') or return;
    $self->print($out, @_);
    $out->close;
    $self;
}

sub print($@)
{   my ($self, $out) = (shift, shift);

    # Collect the labels from the selected messages.
    my %labeled;
    foreach my $message (@_)
    {   my $labels = $message->labels;
        (my $seq   = $message->filename) =~ s!.*/!!;

        push @{$labeled{unseen}}, $seq
            unless $labels->{seen};

        foreach (keys %$labels)
        {   push @{$labeled{$_}}, $seq
                if $labels->{$_};
        }
    }
    delete $labeled{seen};

    # Write it out

    local $"     = ' ';
    foreach (sort keys %labeled)
    {
        my @msgs = @{$labeled{$_}};  #they are ordered already.
        $_ = 'cur' if $_ eq 'current';
        print $out  "$_:";

        while(@msgs)
        {   my $start = shift @msgs;
            my $end   = $start;

            $end = shift @msgs
                 while @msgs && $msgs[0]==$end+1;

            print $out ($start==$end ? " $start" : " $start-$end");
        }
        print $out "\n";
    }

    $self;
}

1;
