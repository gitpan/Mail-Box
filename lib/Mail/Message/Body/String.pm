use strict;
use warnings;

package Mail::Message::Body::String;
use vars '$VERSION';
$VERSION = '2.063';
use base 'Mail::Message::Body';

use Carp;
use Mail::Box::FastScalar;


#------------------------------------------
# The scalar is stored as reference to avoid a copy during creation of
# a string object.

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    delete $self->{MMBS_nrlines};

    local *IN;
    unless(open IN, '<', $filename)
    {   $self->log(ERROR =>
            "Unable to read file $filename for message body scalar: $!");
        return;
    }

    my @lines = <IN>;
    close IN;

    $self->{MMBS_nrlines} = @lines;
    $self->{MMBS_scalar}  = join '', @lines;
    $self;
}

sub _data_from_filehandle(@)
{   my ($self, $fh) = @_;
    if(ref $fh eq 'Mail::Box::FastScalar')
    {   my $lines = $fh->getlines;
        $self->{MMBS_nrlines} = @$lines;
        $self->{MMBS_scalar}  = join '', @$lines;
    }
    else
    {    my @lines = $fh->getlines;
         $self->{MMBS_nrlines} = @lines;
         $self->{MMBS_scalar}  = join '', @lines;
    }
    $self;
}

sub _data_from_glob(@)
{   my ($self, $fh) = @_;
    my @lines = <$fh>;
    $self->{MMBS_nrlines} = @lines;
    $self->{MMBS_scalar}  = join '', @lines;
    $self;
}

sub _data_from_lines(@)
{   my ($self, $lines) = @_;
    $self->{MMBS_nrlines} = @$lines unless @$lines==1;
    $self->{MMBS_scalar}  = @$lines==1 ? shift @$lines : join('', @$lines);
    $self;
}

#------------------------------------------

sub clone()
{   my $self = shift;
    ref($self)->new(data => $self->string, based_on => $self);
}

#------------------------------------------
# Only compute it once, if needed.  The scalar contains lines, so will
# have a \n even at the end.

sub nrLines()
{   my $self = shift;
    return $self->{MMBS_nrlines} if defined $self->{MMBS_nrlines};

    my $nrlines = 0;
    for($self->{MMBS_scalar})
    {   $nrlines++ while /\n/g;
    }

    $self->{MMBS_nrlines} = $nrlines;
}

#------------------------------------------

sub size() { length shift->{MMBS_scalar} }

#------------------------------------------

sub string() { shift->{MMBS_scalar} }

#------------------------------------------

sub lines()
{   my @lines = split /^/, shift->{MMBS_scalar};
    wantarray ? @lines : \@lines;
}

#------------------------------------------

sub file() { Mail::Box::FastScalar->new(shift->{MMBS_scalar}) }

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    if(ref $fh eq 'GLOB') { print $fh $self->{MMBS_scalar} }
    else                  { $fh->print($self->{MMBS_scalar}) }
    $self;
}

#------------------------------------------

sub printEscapedFrom($)
{   my ($self, $fh) = @_;

    my $text = $self->{MMBS_scalar};    # copy required
    $text    =~ s/^(?=\>*From )/>/;
    if(ref $fh eq 'GLOB') { print $fh $text   }
    else                  { $fh->print($text) }
    $self;
}

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    delete $self->{MMBS_nrlines};

    (my $begin, my $end, $self->{MMBS_scalar}) = $parser->bodyAsString(@_);
    $self->fileLocation($begin, $end);

    $self;
}

#------------------------------------------

1;
