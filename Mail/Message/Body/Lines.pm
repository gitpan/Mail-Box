use strict;
use warnings;

package Mail::Message::Body::Lines;
our $VERSION = 2.022;  # Part of Mail::Box
use base 'Mail::Message::Body';

use Mail::Box::Parser;
use IO::Lines;

use Carp;

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    local *IN;

    unless(open IN, '<', $filename)
    {   $self->log(ERROR => "Unable to read file $filename: $!");
        return;
    }

    $self->{MMBL_array} = [ <IN> ];

    close IN;
    $self;
}

sub _data_from_filehandle(@)
{   my ($self, $fh) = @_;
    $self->{MMBL_array} = [ $fh->getlines ];
    $self
}

sub _data_from_glob(@)
{   my ($self, $fh) = @_;
    $self->{MMBL_array} = [ <$fh> ];
    $self;
}

sub _data_from_lines(@)
{   my ($self, $lines)  = @_;
    $lines = [ split /(?<=\n)/, $lines->[0] ] # body passed in one string.
        if @$lines==1;

    $self->{MMBL_array} = $lines;
    $self;
}

sub clone()
{   my $self  = shift;
    ref($self)->new(data => [ $self->lines ] );
}

sub nrLines() { scalar @{shift->{MMBL_array}} }

# Optimized to be computed only once.

sub size()
{   my $self = shift;
    return $self->{MMBL_size} if exists $self->{MMBL_size};

    my $size = 0;
    $size += length $_ foreach @{$self->{MMBL_array}};
    $size += @{$self->{MMBL_array}} if $self->eol eq 'CRLF';
    $self->{MMBL_size} = $size;
}

sub string() { join '', @{shift->{MMBL_array}} }

sub lines()  { wantarray ? @{shift->{MMBL_array}} : \@{shift->{MMBL_array}} }

sub file() { IO::Lines->new(shift->{MMBL_array}) }

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print(@{$self->{MMBL_array}});
}

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    my @lines = $parser->bodyAsList(@_);
    return undef unless @lines;

    $self->fileLocation(shift @lines, shift @lines);
    $self->{MMBL_array} = \@lines;
    $self;
}

1;
