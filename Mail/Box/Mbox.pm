use strict;
package Mail::Box::Mbox;
our $VERSION = 2.031;  # Part of Mail::Box
use base 'Mail::Box::File';

use Mail::Box::Mbox::Message;
use File::Copy 'move';

my $default_folder_dir    = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
my $default_sub_extension = '.d';

sub init($)
{   my ($self, $args) = @_;

    $self->{MBM_sub_ext}    # required for SUPER::init
        = $args->{subfolder_extension} || $default_sub_extension;

    $self->SUPER::init($args);
}

sub create($@)
{   my ($class, $name, %args) = @_;
    $args{folderdir}           ||= $default_folder_dir;
    $args{subfolder_extension} ||= $default_sub_extension;

    $class->SUPER::create($name, %args);
}

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    $name   ||= $args{folder} or return;

    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_sub_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    if(-d $filename)      # fake empty folder, with sub-folders
    {   return 1 unless -f File::Spec->catfile($filename, '1')   # MH
                     || -d File::Spec->catdir($filename, 'cur'); # Maildir
    }

    return 0 unless -f $filename;
    return 1 if -z $filename;      # empty folder is ok

    my $file = IO::File->new($filename, 'r') or return 0;
    local $_;
    while(<$file>)
    {   next if /^\s*$/;           # skip empty lines
        $file->close;
        return m/^From /;          # found Mbox separator?
    }

    return 1;
}

sub writeMessages($)
{   my ($self, $args) = @_;

    $self->SUPER::writeMessages($args) or return;

    if($self->{MB_remove_empty})
    {   # Can the sub-folder directory be removed?  Don't mind if this
        # doesn't work: probably no subdir or still something in it.  This
        # is a rather blunt approach...
        rmdir $self->filename . $self->{MBM_sub_ext};
    }

    $self;
}

sub type() {'mbox'}

sub listSubFolders(@)
{   my ($thingy, %args)  = @_;
    my $class      = ref $thingy || $thingy;

    my $skip_empty = $args{skip_empty} || 0;
    my $check      = $args{check}      || 0;

    my $folder     = exists $args{folder} ? $args{folder} : '=';
    my $folderdir  = exists $args{folderdir}
                   ? $args{folderdir}
                   : $default_folder_dir;

    my $extension  = $args{subfolder_extension};
    my $dir;
    if(ref $thingy)   # Mail::Box::Mbox
    {    $extension ||= $thingy->{MBM_sub_ext};
         $dir      = $thingy->filename;
    }
    else
    {    $extension ||= $default_sub_extension;
         $dir    = $class->folderToFilename($folder, $folderdir, $extension);
    }

    my $real       = -d $dir ? $dir : "$dir$extension";
    return () unless opendir DIR, $real;

    # Some files have to be removed because they are created by all
    # kinds of programs, but are no folders.

    my @entries = grep { ! m/\.lo?ck$/ && ! m/^\./ } readdir DIR;
    closedir DIR;

    # Look for files in the folderdir.  They should be readable to
    # avoid warnings for usage later.  Furthermore, if we check on
    # the size too, we avoid a syscall especially to get the size
    # of the file by performing that check immediately.

    my %folders;  # hash to immediately un-double names.

    foreach (@entries)
    {   my $entry = File::Spec->catfile($real, $_);
        next unless -r $entry;
        if( -f _ )
        {   next if $args{skip_empty} && ! -s _;
            next if $args{check} && !$class->foundIn($entry);
            $folders{$_}++;
        }
        elsif( -d _ )
        {   # Directories may create fake folders.
            if($args{skip_empty})
            {   opendir DIR, $entry or next;
                my @sub = grep !/^\./, readdir DIR;
                closedir DIR;
                next unless @sub;
            }

            (my $folder = $_) =~ s/$extension$//;
            $folders{$folder}++;
        }
    }

    keys %folders;
}

sub dirToSubfolder($$)
{   my ($self, $dir, $extension) = @_;
    $extension ||= $default_sub_extension;

    move $dir, $dir.$extension;
}

sub folderToFilename($$;$)
{   my ($thingy, $name, $folderdir, $extension) = @_;
    return $name if File::Spec->file_name_is_absolute($name);

    $extension ||=
          ref $thingy ? $thingy->{MBM_sub_ext} : $default_sub_extension;

    $name     =~ s#^=#$folderdir/#;
    my @parts = split m!/!, $name;

    my $real  = shift @parts;
    $real     = '/' if $real eq '';

    if(@parts)
    {   my $file  = pop @parts;

        $real = File::Spec->catdir($real.(-d $real ? '' : $extension), $_)
           foreach @parts;

        $real = File::Spec->catfile($real.(-d $real ? '' : $extension), $file);
    }

    $real;
}

1;

1;
