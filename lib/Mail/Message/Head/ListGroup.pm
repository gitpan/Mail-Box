
package Mail::Message::Head::ListGroup;
use vars '$VERSION';
$VERSION = '2.046';
use base 'Mail::Reporter';

use strict;
use warnings;

use Mail::Message::Field::Fast;

use Scalar::Util 'weaken';
use List::Util   'first';
use Sys::Hostname;


sub new(@)
{   my $class = shift;

    my @fields;
    push @fields, shift while ref $_[0];

    $class->SUPER::new(@_, fields => \@fields);
}

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $head = $self->{MMHL_head}
      = $args->{head} || Mail::Message::Head::Partial->new;

    $self->add($_)                     # add specified object fields
        foreach @{$args->{fields}};

    $self->add($_, $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    my $address = $args->{address};
       if(!defined $address) { ; }
    elsif(!ref $address || !$address->isa('Mail::Message::Field::Address'))
    {   require Mail::Message::Field::Address;
        my $mi   = Mail::Message::Field::Address->coerce($address);

        $self->log(ERROR =>
                "Cannot convert \"$address\" into an address object"), return
            unless defined $mi;

        $address = $mi;
    }
    $self->{MMHL_address}  = $address          if defined $args->{address};

    $self->{MMHL_listname} = $args->{listname} if defined $args->{listname};
    $self->{MMHL_version}  = $args->{version}  if defined $args->{version};
    $self->{MMHL_software} = $args->{software} if defined $args->{software};
    $self->{MMHL_rfc}      = $args->{rfc}      if defined $args->{rfc};
    $self->{MMHL_type}     = $args->{type}     if defined $args->{type};

    $self->{MMHL_fns}      = [];
    $self;
}

#------------------------------------------


sub from($)
{  my ($class, $from) = @_;
   my $head = $from->isa('Mail::Message::Head') ? $from : $from->head;
   my $self = $class->new(head => $head);

   return () unless $self->findListFields;
   $self;
}

#------------------------------------------


sub clone()
{   my $self = shift;
    my $clone = bless %$self, ref $self;
    $clone->{MMHL_fns} = [ @{$self->{MMHL_fns}} ];
    $clone;
}

#------------------------------------------


sub head() { shift->{MMHL_head} }

#------------------------------------------


sub attach($)
{   my ($self, $head) = @_;
    my $lg = ref($self)->clone;
    $self->{MMHL_head} = $head;

    $head->add($_->clone) for $self->fields;
    $lg;
}

#------------------------------------------


sub delete()
{   my $self   = shift;
    my $head   = $self->head;
    $head->removeField($_) foreach $self->fields;
    $self;
}

#------------------------------------------


sub add(@)
{   my $self = shift;
    my $field = $self->head->add(@_) or return ();
    push @{$self->{MMHL_fns}}, $field->name;
    $self;
}

#------------------------------------------


sub fields()
{   my $self = shift;
    my $head = $self->head;
    map { $head->get($_) } @{$self->{MMHL_fns}};
}

#------------------------------------------


sub version()
{  my $self = shift;
   $self->type;
   $self->{MMHL_version};
}

#------------------------------------------


sub software()
{  my $self = shift;
   $self->type;
   $self->{MMHL_software};
}

#------------------------------------------


sub rfc()
{  my $self = shift;
   return $self->{MMHL_rfc} if defined $self->{MMHL_rfc};

   my $head = $self->head;
     defined $head->get('List-Post') ? 'rfc2369'
   : defined $head->get('List-Id')   ? 'rfc2918'
   :                                    undef;
}

#------------------------------------------


sub address()
{   my $self = shift;
    return $self->{MMHL_address} if exists $self->{MMHL_address};

    my $type = $self->type || 'Unknown';
    my $head = $self->head;

    my ($field, $address);
    if($type eq 'Smartlist' && defined($field = $head->get('X-Mailing-List')))
    {   $address = $1 if $field =~ m/\<([^>]+)\>/ }
    elsif($type eq 'YahooGroups')
    {   $address = $head->study('X-Apparently-To') }

    $address ||= $head->get('List-Post') || $head->get('Reply-To')
             || $head->get('Sender');
    $address = $address->study if ref $address;

       if(!defined $address) { ; }
    elsif(!ref $address)
    {   $address =~ s/\bowner-|-(?:owner|bounce|admin)\@//i;
        $address = Mail::Message::Field::Address->new(address => $address);
    }
    elsif($address->isa('Mail::Message::Field::Addresses'))
    {   # beautify
        $address     = ($address->addresses)[0];
        my $username = defined $address ? $address->username : '';
        if($username =~ s/^owner-|-(owner|bounce|admin)$//i)
        {   $address = Mail::Message::Field::Address->new
               (username => $username, domain => $address->domain);
        }
    }
    elsif($address->isa('Mail::Message::Field::URIs'))
    {   my $uri  = first { $_->scheme eq 'mailto' } $address->URIs;
        $address = defined $uri
                 ? Mail::Message::Field::Address->new(address => $uri->to)
                 : undef;
    }
    else  # Don't understand life anymore :-(
    {   undef $address;
    }

    $self->{MMHL_address} = $address;
}

#------------------------------------------


sub listname()
{   my $self = shift;
    return $self->{MMHL_listname} if exists $self->{MMHL_listname};

    my $head = $self->head;

    # Some lists have a field with the name only
    my $list = $head->get('List-ID') || $head->get('X-List')
            || $head->get('X-ML-Name');

    my $listname;
    if(defined $list)
    {   $listname = $list->study->decodedBody;
    }
    elsif(my $address = $self->address)
    {   $listname = $address->phrase || $address->address;
    }

    $self->{MMHL_listname} = $listname;
}

#------------------------------------------


sub type()
{   my $self = shift;
    return $self->{MMHL_type} if exists $self->{MMHL_type};

    my $head = $self->head;
    my ($type, $software, $version, $field);

    if(my $commpro = $head->get('X-ListServer'))  
    {   ($software, $version) = $commpro =~ m/^(.*)\s+LIST\s*([\d.]+)\s*$/;
        $type    = 'CommuniGate';
    }
    elsif(my $mailman = $head->get('X-Mailman-Version'))
    {   $version = "$mailman";
        $type    = 'Mailman';
    }
    elsif(my $majordomo = $head->get('X-Majordomo-Version'))
    {   $version = "$majordomo";
        $type    = 'Majordomo';
    }
    elsif(my $ecartis = $head->get('X-Ecartis-Version'))
    {   ($software, $version) = $ecartis =~ m/^(.*)\s+(v[\d.]+)/;
        $type    = 'Ecartis';
    }
    elsif(my $listar = $head->get('X-Listar-Version'))
    {   ($software, $version) = $listar =~ m/^(.*?)\s+(v[\w.]+)/;
        $type    = 'Listar';
    }
    elsif(defined($field = $head->get('List-Software'))
          && $field =~ m/listbox/i)
    {   ($software, $version) = $field =~ m/^(\S*)\s*(v[\d.]+)\s*$/;
        $type    = 'Listbox';
    }
    elsif(defined($field = $head->get('X-Mailing-List'))
          && $field =~ m[archive/latest])
    {   $type    = 'Smartlist' }
    elsif(defined($field = $head->get('Mailing-List')) && $field =~ m/yahoo/i )
    {   $type    = 'YahooGroups' }
    elsif(defined($field) && $field =~ m/(ezmlm)/i )
    {   $type    = 'Ezmlm' }
    elsif(my $fml = $head->get('X-MLServer'))
    {   ($software, $version) = $fml =~ m/^\s*(\S+)\s*\[\S*\s*([^\]]*?)\s*\]/;
        $type    = 'FML';
    }
    elsif(defined($field = $head->get('List-Subscribe')
                        || $head->get('List-Unsubscribe'))
          && $field =~ m/sympa/i)
    {   $type    = 'Sympa' }
    elsif(first { m/majordom/i } $head->get('Received'))
    {   # Majordomo is hard to recognize
        $type    = "Majordomo";
    }
    elsif($field = $head->get('List-ID') && $field =~ m/listbox\.com/i)
    {   $type    = "Listbox" }

    $self->{MMHL_version}  = $version  if defined $version;
    $self->{MMHL_software} = $software if defined $software;
    $self->{MMHL_type}     = $type;
}

#------------------------------------------


our $list_field_names
  = qr/ ^ (?: List|X-Envelope|X-Original ) - 
      | ^ (?: Precedence|Mailing-List ) $
      | ^ X-(?: Loop|BeenThere|Sequence|List|Sender|MLServer ) $
      | ^ X-(?: Mailman|Listar|Egroups|Encartis|ML ) -
      | ^ X-(?: Archive|Mailing|Original|Mail|ListServer ) -
      | ^ (?: Mail-Followup|Delivered|Errors|X-Apperently ) -To $
      /xi;

sub findListFields()
{   my $self = shift;
    my @names = map { $_->name } $self->head->grepNames($list_field_names);
    $self->{MMHL_fns} = \@names;
    @names;
}

#------------------------------------------


sub print(;$)
{   my $self = shift;
    my $out  = shift || select;
    $self->print($out) foreach $self->fields;
}

#------------------------------------------


sub details()
{   my $self     = shift;
    my $type     = $self->type || 'Unknown';

    my $software = $self->software;
    undef $software if defined($software) && $type eq $software;
    my $version  = $self->version;
    my $release
      = defined $software
      ? (defined $version ? " ($software $version)" : " ($software)")
      : (defined $version ? " ($version)"           : '');

    my $address  = $self->address || 'unknown address';
    my $fields   = scalar $self->fields;
    "$type at $address$release, $fields fields";
}

#------------------------------------------


1;
