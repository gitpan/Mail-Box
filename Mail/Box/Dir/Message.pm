use strict;
use warnings;

package Mail::Box::Dir::Message;
our $VERSION = 2.022;  # Part of Mail::Box
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->filename($args->{filename})
        if $args->{filename};

    $self;
}

sub print(;$)
{   my $self     = shift;
    my $out      = shift || select;

    return $self->SUPER::print($out)
        if $self->modified;

    my $filename = $self->filename;
    if($filename && -r $filename)
    {   copy($filename, $out);
        return $self;
    }

    $self->SUPER::print($out);

    1;
}

sub filename(;$)
{   my $self = shift;
    @_ ? $self->{MBDM_filename} = shift : $self->{MBDM_filename};
}

sub diskDelete()
{   my $self = shift;
    $self->SUPER::diskDelete;

    my $filename = $self->filename;
    unlink $filename if $filename;
    $self;
}

sub parser()
{   my $self   = shift;

    my $parser = Mail::Box::Parser->new
      ( filename  => $self->{MBDM_filename}
      , mode      => 'r'
      , $self->logSettings
      );

    unless($parser)
    {   $self->log(ERROR => "Cannot create parser for $self->{MBDM_filename}.");
        return;
    }

    $parser;
}

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    my $folder   = $self->folder;
    $folder->lazyPermitted(1);

    my $parser   = $self->parser or return;
    $self->readFromParser($parser);
    $parser->stop;

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head.');
    $self->head;
}

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->head;
    my $parser   = $self->parser or return;

    if($head->isDelayed)
    {   $head = $self->readHead($parser);
        if(defined $head)
        {   $self->log(PROGRESS => 'Loaded delayed head.');
            $self->head($head);
        }
        else
        {   $self->log(ERROR => 'Unable to read delayed head.');
            return;
        }
    }
    else
    {   my ($begin, $end) = $body->fileLocation;
        $parser->filePosition($begin);
    }

    my $newbody  = $self->readBody($parser, $head);
    $parser->stop;

    unless(defined $newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);
}

sub create($)
{   my ($self, $filename) = @_;

    my $old = $self->filename || '';
    return $self if $filename eq $old && !$self->modified;

    # Write the new data to a new file.

    my $new     = $filename . '.new';
    my $newfile = IO::File->new($new, 'w');
    $self->log(ERROR => "Cannot write message to $new: $!"), return
        unless $newfile;

    $self->print($newfile);
    $newfile->close;

    # Accept the new data
# maildir produces warning where not expected...
#   $self->log(WARNING => "Failed to remove $old: $!")
#       if $old && !unlink $old;

    unlink $old if $old;

    $self->log(ERROR => "Failed to move $new to $filename: $!"), return
         unless move($new, $filename);

    $self->modified(0);
    $self->Mail::Box::Dir::Message::filename($filename);

    $self;
}

1;