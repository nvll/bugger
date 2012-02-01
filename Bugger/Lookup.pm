#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use Mail::MboxParser;

package         Bugger::Lookup;
require         Exporter;

our @ISA        = qw(Exporter);
our @EXPORT     = qw(Lookup);

sub new {
    my $caller = shift;
    my $class = ref $caller || $caller;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

sub get {
	my $self = shift;
	my $this_bug = shift;
	my $ua = LWP::UserAgent->new;
	my $response = $ua->get("http://bugs.debian.org/mbox:$this_bug");

	if (! $response->is_success) {
		return "Could not download mbox for $this_bug.";
	}

	my $text = $response->content;
	my $mb = Mail::MboxParser->new(\$text, decode => 'ALL');
	my @mbox;

	# simpler abstraction
	while (my $msg = $mb->next_message) {
		my %this;
		
		$this{'from'} = $msg->header->{'from'};
		$this{'subject'} = $msg->header->{'subject'};
		$this{'body'} = $msg->body($msg->find_body, 0);

		push @mbox, \%this;
	}

	return \@mbox;
}

sub package {
    my $self = shift;
    my $package = shift;
    if (!defined $package) {
        return 1;
    }
    
    # TODO: Remove LWP and fork to a wget process and pass the data to the
    # parent through a filehandle. This way the GUI can update during idle
    # and it also gives us the ability to have a 'cancel' button (kill the
    # pid).
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get("http://bugs.debian.org/cgi-bin/pkgreport.cgi?pkg=$package");
    if (!$response->is_success) {
        die "Could not fetch bugs for $ARGV[0]\n";        
    }

    my $test = $response->content;
    my @clean = ('<em>',
                '</em>',
                '<strong>',
                '</strong>',
                '&lt;',
                '&gt;',
                '&quot;');
    my @bug_glob = split /\n/, $test;
    my @bug_list;
    my %current_bug = ('number' => undef,
                       'subject' => undef,
                       'severity' => undef,
                       'submitter' => undef,
                       'tags' => undef);
    my $current_bug;

    foreach (@bug_glob) {
        if (/\#([0-9]*):\s(.*)<\/a>/) {
            if (defined $current_bug{number}) {
                $current_bug{severity} = "normal" if !defined $current_bug{severity};
                my %tmp = %current_bug;
                push @bug_list, \%tmp;
            
                %current_bug = ('number' => undef,
                                'subject' => undef,
                                'severity' => undef,
                                'submitter' => undef,
                                'tags' => undef);
            }
            $current_bug{number} = $1;
            $current_bug{subject} = html_strip($2);
        } elsif (/Severity: (.*);/) {
            my $severity = $1;
            $severity =~ s/$_//g foreach @clean;
            $current_bug{severity} = $severity;
        } elsif (/Reported by:\s\<.*\>(.*)\s(.*)\<.*\>/)  {
            my ($name, $email) = ($1, $2);
            $name =~ s/$_//g foreach @clean;
            $email =~ s/$_//g foreach @clean;
            $current_bug{submitter} = "$name <$email>";
        } elsif (/Tags: (.*);/) {
            my $tags = $1;
            $tags =~ s/$_//g foreach @clean;
            $current_bug{tags} = $tags;
        }
      
    }
    $current_bug{severity} = "normal" if !defined $current_bug{severity};
    my %tmp = %current_bug;
    push @bug_list, \%tmp;
    %current_bug = ();
    return @bug_list;
}

sub html_strip
{
	my %filter = (
		'&quot;' => '"',
		'&gt;' => '>',
		'&lt;' => '<',
		'&amp;' => '\&'
	);

	my $arg = shift;

	while (my ($k, $v) = each(%filter)) {
		$arg =~ s/$k/$v/g;
	}
	
	return $arg;
}
