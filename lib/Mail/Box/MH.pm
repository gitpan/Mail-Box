
use strict;
package Mail::Box::MH;
use vars '$VERSION';
$VERSION = '2.046';
use base 'Mail::Box::Dir';

use Mail::Box::MH::Index;
use Mail::Box::MH::Message;
use Mail::Box::MH::Labels;

use Carp;
use IO::File;
use File::Spec;
use File::Basename;


my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.mh" : '.';

sub init($)
{   my ($self, $args) = @_;

    $args->{folderdir}     ||= $default_folder_dir;
    $args->{lock_file}     ||= $args->{index_filename};

    $self->SUPER::init($args);

    my $folderdir            = $self->folderdir;
    my $directory            = $self->directory;
    return unless -d $directory;

    # About the index

    $self->{MBM_keep_index}  = $args->{keep_index} || 0;
    $self->{MBM_index}       = $args->{index};
    $self->{MBM_index_type}  = $args->{index_type} || 'Mail::Box::MH::Index';
    for($args->{index_filename})
    {  $self->{MBM_index_filename}
          = !defined $_ ? File::Spec->catfile($directory, '.index') # default
          : File::Spec->file_name_is_absolute($_) ? $_              # absolute
          :               File::Spec->catfile($directory, $_);      # relative
    }

    # About labels

    $self->{MBM_labels}      = $args->{labels};
    $self->{MBM_labels_type} = $args->{labels_type} || 'Mail::Box::MH::Labels';
    for($args->{labels_filename})
    {   $self->{MBM_labels_filename}
          = !defined $_ ? File::Spec->catfile($directory, '.mh_sequences')
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_);       # relative
    }

    $self;
}

#-------------------------------------------


sub create($@)
{   my ($thingy, $name, %args) = @_;
    my $class     = ref $thingy      || $thingy;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    return $class if -d $directory;

    if(mkdir $directory, 0700)
    {   $class->log(PROGRESS => "Created folder $name.\n");
        return $class;
    }
    else
    {   $class->log(ERROR => "Cannot create MH folder $name: $!\n");
        return;
    }
}

#-------------------------------------------

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    return 0 unless -d $directory;
    return 1 if -f File::Spec->catfile($directory, "1");

    # More thorough search required in case some numbered messages
    # disappeared (lost at fsck or copy?)

    return unless opendir DIR, $directory;
    foreach (readdir DIR)
    {   next unless m/^\d+$/;   # Look for filename which is a number.
        closedir DIR;
        return 1;
    }

    closedir DIR;
    0;
}

#-------------------------------------------

sub type() {'mh'}

#-------------------------------------------

sub listSubFolders(@)
{   my ($class, %args) = @_;
    my $dir;
    if(ref $class)
    {   $dir   = $class->directory;
        $class = ref $class;
    }
    else
    {   my $folder    = $args{folder}    || '=';
        my $folderdir = $args{folderdir} || $default_folder_dir;
        $dir   = $class->folderToDirectory($folder, $folderdir);
    }

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    # Read the directories from the directory, to find all folders
    # stored here.  Some directories have to be removed because they
    # are created by all kinds of programs, but are no folders.

    return () unless -d $dir && opendir DIR, $dir;

    my @dirs = grep { !/^\d+$|^\./ && -d File::Spec->catfile($dir,$_) && -r _ }
                   readdir DIR;

    closedir DIR;

    # Skip empty folders.  If a folder has sub-folders, then it is not
    # empty.
    if($args{skip_empty})
    {    my @not_empty;

         foreach my $subdir (@dirs)
         {   if(-f File::Spec->catfile($dir,$subdir, "1"))
             {   # Fast found: the first message of a filled folder.
                 push @not_empty, $subdir;
                 next;
             }

             opendir DIR, File::Spec->catfile($dir,$subdir) or next;
             my @entities = grep !/^\./, readdir DIR;
             closedir DIR;

             if(grep /^\d+$/, @entities)   # message 1 was not there, but
             {   push @not_empty, $subdir; # other message-numbers exist.
                 next;
             }

             foreach (@entities)
             {   next unless -d File::Spec->catfile($dir,$subdir,$_);
                 push @not_empty, $subdir;
                 last;
             }

         }

         @dirs = @not_empty;
    }

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};

    grep { $class->foundIn(File::Spec->catfile($dir,$_)) } @dirs;
}

#-------------------------------------------

sub nameOfSubFolder($@)
{   my ($self, $name) = (shift, shift);
    File::Spec->catfile($self->directory, $name);
}

#-------------------------------------------

sub openSubFolder($)
{   my ($self, $name) = @_;

    my $subdir = $self->nameOfSubFolder($name);
    unless(-d $subdir || mkdir $subdir, 0755)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->SUPER::openSubFolder($name, @_);
}

#-------------------------------------------


sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message} ? $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $self     = $class->new(@_, access => 'a')
        or return ();

    my $directory= $self->directory;
    return unless -d $directory;

    my $locker   = $self->locker;
    unless($locker->lock)
    {   $self->log(ERROR => "Cannot append message without lock on $self.");
        return;
    }

    my $msgnr    = $self->highestMessageNumber +1;

    foreach my $message (@messages)
    {   my $filename = File::Spec->catfile($directory,$msgnr);
        $message->create($filename)
          or $self->log(ERROR => "Unable to write message for $self to $filename: $!\n");

        $msgnr++;
    }
 
    my $labels   = $self->labels->append(@messages);

    $locker->unlock;
    $self->close;

    @messages;
}

#-------------------------------------------


sub highestMessageNumber()
{   my $self = shift;

    return $self->{MBM_highest_msgnr}
        if exists $self->{MBM_highest_msgnr};

    my $directory    = $self->directory;

    opendir DIR, $directory or return;
    my @messages = sort {$a <=> $b} grep /^\d+$/, readdir DIR;
    closedir DIR;

    $messages[-1];
}

#-------------------------------------------


sub index()
{   my $self  = shift;
    return () unless $self->{MBM_keep_index};
    return $self->{MBM_index} if defined $self->{MBM_index};

    $self->{MBM_index} = $self->{MBM_index_type}->new
     ( filename  => $self->{MBM_index_filename}
     , $self->logSettings
     )

}

#-------------------------------------------


sub labels()
{   my $self   = shift;
    return $self->{MBM_labels} if defined $self->{MBM_labels};

    $self->{MBM_labels} = $self->{MBM_labels_type}->new
      ( filename => $self->{MBM_labels_filename}
      , $self->logSettings
      )
}

#-------------------------------------------

sub readMessageFilenames
{   my ($self, $dirname) = @_;

    opendir DIR, $dirname or return;
    my @msgnrs
       = sort {$a <=> $b}
            grep { /^\d+$/ && -f File::Spec->catfile($dirname,$_) }
               readdir DIR;

    closedir DIR;

    @msgnrs;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    my $locker = $self->locker;
    $locker->lock or return;

    my @msgnrs = $self->readMessageFilenames($directory);

    my $index  = $self->{MBM_index};
    unless($index)
    {   $index = $self->index;
        $index->read if $index;
    }

    my $labels = $self->{MBM_labels};
    unless($labels)
    {    $labels = $self->labels;
         $labels->read if $labels;
    }

    my $body_type   = $args{body_delayed_type};
    my $head_type   = $args{head_delayed_type};
    my @log         = $self->logSettings;

    foreach my $msgnr (@msgnrs)
    {
        my $msgfile = File::Spec->catfile($directory, $msgnr);

        my $head;
        $head       = $index->get($msgfile) if $index;
        $head     ||= $head_type->new(@log);

        my $message = $args{message_type}->new
         ( head       => $head
         , filename   => $msgfile
         , folder     => $self
         , fix_header => $self->{MB_fix_headers}
         );

        my $labref  = $labels ? $labels->get($msgnr) : ();
        $message->label(seen => 1, $labref ? @$labref : ());

        $message->storeBody($body_type->new(@log, message => $message));
        $self->storeMessage($message);
    }

    $self->{MBM_highest_msgnr}  = $msgnrs[-1];
    $self;
}
 
#-------------------------------------------


sub writeMessages($)
{   my ($self, $args) = @_;

    # Write each message.  Two things complicate life:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $locker    = $self->locker;
    $self->log(ERROR => "Cannot write folder $self without lock."), return
        unless $locker->lock;

    my $renumber  = exists $args->{renumber} ? $args->{renumber} : 1;
    my $directory = $self->directory;
    my @messages  = @{$args->{messages}};

    my $writer    = 0;
    foreach my $message (@messages)
    {
        my $filename = $message->filename;

        my $newfile;
        if($renumber || !$filename)
        {   $newfile = $directory . '/' . ++$writer;
        }
        else
        {   $newfile = $filename;
            $writer  = basename $filename;
        }

        $message->create($newfile);
    }

    # Write the labels- and the index-file.

    my $labels = $self->labels;
    $labels->write(@messages) if $labels;

    my $index  = $self->index;
    $index->write(@messages) if $index;

    $locker->unlock;

    # Remove an empty folder.  This is done last, because the code before
    # in this method will have cleared the contents of the directory.

    if(!@messages && $self->{MB_remove_empty})
    {   # If something is still in the directory, this will fail, but I
        # don't mind.
        rmdir $directory;
    }

    $self;
}

#-------------------------------------------

#-------------------------------------------


1;
