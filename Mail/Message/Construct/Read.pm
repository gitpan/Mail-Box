
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.042';


sub read($@)
{   my ($class, $from) = (shift, shift);
    my ($filename, $file);
    my $ref       = ref $from;

    require IO::Scalar;

    if(!$ref)
    {   $filename = 'scalar';
        $file     = IO::Scalar->new(\$from);
    }
    elsif($ref eq 'SCALAR')
    {   $filename = 'ref scalar';
        $file     = IO::Scalar->new($from);
    }
    elsif($ref eq 'ARRAY')
    {   $filename = 'array of lines';
        my $buffer= join '', @$from;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        local $/;
        my $buffer= <$from>;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        my $buffer= join '', $from->getlines;
        $file     = IO::Scalar->new(\$buffer);
    }
    else
    {   croak "Cannot read from $from";
    }

    require Mail::Box::Parser::Perl;  # not parseable by C parser
    my $parser = Mail::Box::Parser::Perl->new
     ( filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $self = $class->new(@_);
    $self->readFromParser($parser);
    $parser->stop;

    my $head = $self->head;
    $head->set('Message-ID' => $self->messageId)
        unless $head->get('Message-ID');

    $self->statusToLabels;
    $self;
}

1;
