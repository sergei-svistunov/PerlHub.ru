package Dpkg::Deps::KnownFacts::PerlHub;

use qbit;

require Dpkg::Deps;

use base qw(Dpkg::Deps::KnownFacts);

sub _find_package {
    my ($self, $dep) = @_;

    my $pkg = $dep->{'package'};

    return unless exists($self->{'pkg'}{$pkg});

    foreach my $p (@{$self->{pkg}{$pkg}}) {
        return $p unless defined($dep->{'relation'}) && defined($dep->{'version'});
        return $p if Dpkg::Version::version_compare_relation($p->{'version'}, $dep->{'relation'}, $dep->{'version'});
    }

    return;
}

TRUE;
