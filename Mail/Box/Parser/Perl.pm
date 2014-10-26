use strict;
use warnings;

package Mail::Box::Parser::Perl;
our $VERSION = 2.022;  # Part of Mail::Box
use base 'Mail::Box::Parser';

use Mail::Message::Field;
use List::Util 'sum';
use FileHandle;

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $filename = $args->{filename};
    my $file     = $args->{file};
    $file        = FileHandle->new($filename, $self->{MBP_mode})
        unless defined $file;

    return unless $file;
#   binmode $file, ':raw';

    $self->{MBPP_file}       = $file;
    $self->{MBPP_filename}   = $filename;
    $self->{MBPP_separator}  = $args->{separator} || undef;
    $self->{MBPP_separators} = [];
    $self->{MBPP_trusted}    = $args->{trusted};

    # Prepare the first line.
    $self->{MBPP_start_line} = 0;

    my $line  = $file->getline || return $self;
    $line     =~ s/[\012\015]+$/\n/;
    $self->{MBP_linesep}     = $1;
    $file->seek(0, 0);

#   binmode $file, ':crlf' if $] < 5.007;  # problem with perlIO

    $self->log(PROGRESS => "Opened folder from file $filename.");

    $self;
}

sub start(@)
{   my $self = shift;
    $self->SUPER::start(trust_file => $self->{MBPP_trusted}, @_);
}

sub stop(@)
{   my $self = shift;
    $self->closeFile;
    $self->SUPER::stop(@_);
}

sub closeFile()
{   my $self = shift;
    my $file = delete $self->{MBPP_file} or return;
    $file->close;

    delete $self->{MBPP_separators};
    delete $self->{MBPP_strip_gt};
    $self;
}

sub pushSeparator($)
{   my ($self, $sep) = @_;
    unshift @{$self->{MBPP_separators}}, $sep;
    $self->{MBPP_strip_gt}++ if $sep =~ m/^From /;
    $self;
}

sub popSeparator()
{   my $self = shift;
    my $sep  = shift @{$self->{MBPP_separators}};
    $self->{MBPP_strip_gt}-- if $sep =~ m/^From /;
    $sep;
}

sub filePosition(;$)
{   my $self = shift;
    @_ ? seek($self->{MBPP_file}, shift, 0) : tell $self->{MBPP_file};
}

my $empty = qr/^[\015\012]*$/;

sub readHeader()
{   my $self  = shift;
    my $file  = $self->{MBPP_file};

    my $start = $file->tell;
    my @ret   = ($start, undef);
    my $line  = $file->getline;

LINE:
    while(defined $line)
    {   last if $line =~ $empty;
        my ($name, $body) = split /\s*\:\s*/, $line, 2;

        unless(defined $body)
        {   $self->log(WARNING => "Unexpected end of header:\n $line");
            $file->seek(-length $line, 1);
            last LINE;
        }

        # Collect folded lines
        while($line = $file->getline)
        {   $line =~ m!^[ \t]! ? ($body .= $line) : last;
        }

        push @ret, [ $name, $body ];
    }

    $ret[1]  = $file->tell;
    @ret;
}

sub _is_good_end($)
{   my ($self, $where) = @_;

    # No seps, then when have to trust it.
    my $sep = $self->{MBPP_separators}[0];
    return 1 unless defined $sep;

    my $file = $self->{MBPP_file};
    my $here = $file->tell;
    $file->seek($where, 0);

    # Find first non-empty line on specified location.
    my $line = $file->getline;
    $line    = $file->getline while defined $line && $line =~ $empty;

    $file->seek($here, 0);
    return 1 unless defined $line;

    substr($line, 0, length $sep) eq $sep
    && ($sep !~ m/^From / || $line =~ m/ (19[789]|20[01])\d\b/ );
}

sub readSeparator()
{   my $self = shift;

    my $sep   = $self->{MBPP_separators}[0];
    return () unless defined $sep;

    my $file  = $self->{MBPP_file};
    my $start = $file->tell;

    my $line  = $file->getline;
    $line     = $file->getline while defined $line && $line =~ $empty;
    return () unless defined $line;

    $line     =~ s/[\012\015\s]+$/\n/g;
    return ($start, $line)
        if substr($line, 0, length $sep) eq $sep;

    $file->seek($start, 0);
    ();
}

sub _read_stripped_lines(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    $exp_lines  = -1 unless defined $exp_lines;
    my @seps    = @{$self->{MBPP_separators}};

    my $file    = $self->{MBPP_file};
    my @lines   = ();

    if(@seps && $self->{MBPP_trusted})
    {   my $sep  = $seps[0];
        my $l    = length $sep;

        while(my $line = $file->getline)
        {
            if(substr($line, 0, $l) eq $sep
              && ($sep !~ m/^From / || $line =~ m/ (19[789]\d|20[01]\d)/ ))
            {   $file->seek(-length($line), 1);
                last;
            }

            push @lines, $line;
        }
    }
    elsif(@seps)
    {

  LINE: while(my $line = $file->getline)
        {
            foreach my $sep (@seps)
            {   if(substr($line, 0, length $sep) eq $sep
                   && ($sep !~ m/^From / || $line =~ m/ (19[789]\d|20[01]\d)/ ))
                {   $file->seek(-length $line, 1);
                    last LINE;
                }
            }

            $line =~ s/\015?$//;
            push @lines, $line;
        }
    }
    else
    {   # File without separators.
        @lines = $file->getlines;
    }

    if($exp_lines > 0 )
         { pop @lines while @lines > $exp_lines && $lines[-1] =~ $empty }
    else { pop @lines    if @lines              && $lines[-1] =~ $empty }

    map { s/^\>(\>*From\s)/$1/ } @lines
        if $self->{MBPP_strip_gt};

    \@lines;
}

sub _take_scalar($$)
{   my ($self, $begin, $end) = @_;
    my $file = $self->{MBPP_file};
    $file->seek($begin, 0);

    my $return;
    $file->read($return, $end-$begin);
    $return =~ s/\015?//g;
    $return;
}

sub bodyAsString(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    if(defined $exp_chars && $exp_chars>=0)
    {   # Get at once may be successful
        my $end = $begin + $exp_chars;

        if($self->_is_good_end($end))
        {   my $body = $self->_take_scalar($begin, $end);
            $body =~ s/^\>(\>*From\s)/$1/gm if $self->{MBPP_strip_gt};
            return ($begin, $file->tell, $self->_take_scalar($begin, $end))
        }
    }

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    return ($begin, $file->tell, join('', @$lines));
}

sub bodyAsList(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    ($begin, $file->tell, @$lines);
}

sub bodyAsFile($;$$)
{   my ($self, $out, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);

    $out->print($_) foreach @$lines;
    ($begin, $file->tell, scalar @$lines);
}

sub bodyDelayed(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    if(defined $exp_chars)
    {   my $end = $begin + $exp_chars;

        if($self->_is_good_end($end))
        {   $file->seek($end, 0);
            return ($begin, $end, $exp_chars, $exp_lines);
        }
    }

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    my $chars = sum(map {length} @$lines);
    ($begin, $file->tell, $chars, scalar @$lines);
}

1;
