use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
our $VERSION = 2.035;  # Part of Mail::Box
use base 'Mail::Message::TransferEnc';

sub name() { 'quoted-printable' }

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

sub decode($@)
{   my ($self, $body, %args) = @_;

    my @lines;
    foreach ($body->lines)
    {   s/\s+$//;
        s/=0[dD]$//;
        s/\=([A-Fa-f0-9]{2})/
            my $code = hex $1;
              $code == 9  ? "\t"
            : $code < 040 ? sprintf('\\%03o', $code)
            : chr $code
         /ge;

        $_ .= "\n" unless s/\=$//;
        push @lines, $_;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

sub encode($@)
{   my ($self, $body, %args) = @_;

    my @lines;

    # All special characters and whitespace at end of line must be
    # encoded into lines shorter than 76 chars.

    foreach my $line ($body->lines)
    {   chomp $line;
        while(length $line)
        {   my $maxline = 76;
            my $part;

            while(1)
            {   my $changes;
                $part   = substr $line, 0, $maxline;
                my $all = (length $part==length $line);
                for($part)
                {   $changes  = tr/ \t!-<>-~]//c;
                    $changes += 1 if $all && m/[ \t]$/;
                }
                last if length($part) + $changes*2 + ($all ? 0 : 1) <= 76;
                $maxline--;
            }

            substr $line, 0, $maxline, '';

            for($part)
            {   s/[^ \t!-<>-~]/sprintf '=%02X', ord $&/ge;
                s/[ \t]$/ join '', map {sprintf '=%02X', ord $_} $&/gem;
            }

            push @lines, $part . (length($line) ? '=' : '') .  "\n";
        }
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'quoted-printable'
     , data              => \@lines
     );
}

1;
