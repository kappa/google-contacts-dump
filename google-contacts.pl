#!/usr/bin/perl
use uni::perl;

# simple Google Contacts dumper
# by Alex Kapranoff <kappa@cpan.org>
# uses API v3.0, so all fields are dumped, not a subset
# 
# best used as a backup tool run silently from cron
#
# based on http://github.com/miyagawa/google-contacts-gravatar

package Google::Contacts::Dump;
use Any::Moose;
use Net::Google::AuthSub;
use LWP::UserAgent;
use XML::LibXML::Simple;
use Data::Dumper;

with any_moose('X::Getopt');

has authsub => (
    is => 'rw', isa => 'Net::Google::AuthSub',
    default => sub { Net::Google::AuthSub->new(service => 'cp') },
    lazy => 1,
);

has agent => (
    is => 'rw', isa => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy => 1,
);

has auth_params => (
    is => 'rw', isa => 'HashRef',
);

has email => (
    is => 'rw', isa => 'Str', required => 1,
);

has password => (
    is => 'rw', isa => 'Str', required => 1,
);

has max_results => (
    is => 'rw', isa => 'Int', default => 5000,
);

has contacts => (
    is => 'rw', isa => 'ArrayRef',
);

has debug => (
    is => 'rw', isa => 'Bool', default => 0,
);

sub run {
    my $self = shift;

    $self->authorize();
    $self->retrieve_contacts();

    $self->dump_contacts();
}

sub authorize {
    my $self = shift;

    my $resp = $self->authsub->login($self->email, $self->password);
    $resp && $resp->is_success or die "Auth failed against " . $self->email;
    $self->auth_params({ $self->authsub->auth_params });
}

sub retrieve_contacts {
    my $self = shift;

    my $feed = $self->get_feed("contacts/default/full", 'max-results' => $self->max_results);
    $self->contacts($feed->{entry});
}

sub degoogle($) {
    my $ar = shift;

    for my $i (@$ar) {
    	delete $i->{primary} if @$ar == 1;

    	$i->{rel} =~ s/^[^#]+#// if $i->{rel};
    }

    return $ar;
}

sub clean_undef {
    my %hash = @_;

    foreach (keys %hash) {
        delete $hash{$_} unless $hash{$_};
        delete $hash{$_}
            if (ref $hash{$_} eq 'ARRAY' && @{$hash{$_}} == 0);
    }

    return \%hash;
}

sub dump_contacts {
    my $self = shift;

    my %new_keys;
    my @sane;
    for my $c (@{$self->contacts}) {
    	my %sane;

    	$sane{emails}   = degoogle $c->{'gd:email'};
    	$sane{phones}   = degoogle $c->{'gd:phoneNumber'};
    	$sane{address}  = degoogle $c->{'gd:structuredPostalAddress'};
        $sane{title}    = $c->{title};
        $sane{name}     = $c->{'gd:name'};
    	$sane{org}      = degoogle $c->{'gd:organization'};
    	$sane{updated}  = $c->{updated};
    	$sane{website}  = $c->{'gContact:website'};
    	$sane{birthday} = $c->{'gContact:birthday'};
    	$sane{nickname} = $c->{'gContact:nickname'};

    	push @sane, clean_undef %sane;

    	$new_keys{$_}++ for keys %$c;
    }

    delete @new_keys{qw/gd:email gd:phoneNumber title updated id link
    content category gd:organization gd:postalAddress
    gContact:groupMembershipInfo gContact:website gContact:birthday
    gContact:nickname gd:etag gd:name gd:structuredPostalAddress
    app:edited/};

    #say Dumper($self->contacts);
    say Dumper(\@sane);
    #say "Number of " . @sane;
    #say Dumper([keys %new_keys]);
}

sub get_feed {
    my($self, $path, %param) = @_;

    my $uri = URI->new("http://www.google.com/m8/feeds/$path");
    $param{v} = '3.0';
    $uri->query_form(%param);
    my $res = $self->agent->get($uri, %{ $self->auth_params });
    $res->is_success or die "HTTP error for $uri: " . $res->status_line;

    return XML::LibXML::Simple->new->XMLin($res->content, KeyAttr => [], ForceArray => [ 'gd:email' ]);
}

package main;
Google::Contacts::Dump->new_with_options->run;
