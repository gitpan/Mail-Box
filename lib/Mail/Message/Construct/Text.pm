
use strict;

package Mail::Message;
use vars '$VERSION';
$VERSION = '2.044';

use IO::Lines;


sub string()
{   my $self = shift;
    $self->head->string . $self->body->string;
}

#------------------------------------------


sub lines()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    wantarray ? @lines : \@lines;
}

#------------------------------------------


sub file()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    $file->setpos(0,0);
    $file;
}

#------------------------------------------


sub printStructure(;$$)
{   my $self    = shift;
    my $indent  = @_ && !ref $_[-1] && substr($_[-1], -1, 1) eq ' ' ? pop : '';
    my $fh      = @_ ? shift : select;

    my $subject = $self->get('Subject') || '';
    $subject    = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type') || '';
    my $size    = $self->size;
    my $deleted = $self->can('isDeleted') && $self->isDeleted ? ', deleted' : '';

    my $text    = "$indent$type$subject ($size bytes$deleted)\n";
    ref $fh eq 'GLOB' ? (print $fh $text) : $fh->print($text);

    my $body    = $self->body;
    my @parts
      = $body->isMultipart ? $body->parts
      : $body->isNested    ? ($body->nested)
      :                      ();

    $_->printStructure($fh, $indent.'   ') foreach @parts;
}
    
1;
