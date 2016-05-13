package PerlHub::Application::Model::DistPackage;

use qbit;

use base qw(QBit::Application::Model::DBManager);

use LWP::UserAgent;
use IO::Uncompress::Gunzip;

__PACKAGE__->model_accessors(
    db                         => 'PerlHub::Application::Model::DB::Package',
    package_build_wait_depends => 'PerlHub::Application::Model::PackageBuildWaitDepends',
);

__PACKAGE__->model_fields(
    series_id => {db => TRUE, pk => TRUE},
    arch_id   => {db => TRUE, pk => TRUE},
    name      => {db => TRUE, pk => TRUE},
    version   => {db => TRUE, pk => TRUE},
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        series_id => {type => 'number', label => d_gettext('Seried ID')},
        arch_id   => {type => 'number', label => d_gettext('Arch ID')},
        name      => {type => 'text',   label => d_gettext('Name')},
        version   => {type => 'text',   label => d_gettext('Version')},
    }
);

sub init {
    my ($self) = @_;

    $self->{'ua'} = LWP::UserAgent->new();
}

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->dist_package,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub update {
    my ($self) = @_;

    foreach my $series (@{$self->db->package_series->get_all(fields => [qw(id name)], filter => {outdated => 0})}) {
        foreach
          my $arch (@{$self->db->package_arch->get_all(fields => [qw(id name)], filter => [name => '<>' => \'all'])})
        {
            my %component_statuses;
            foreach my $component ($self->get_components()) {
                my $pkg_list;
                my $url = "http://ru.archive.ubuntu.com/"
                  . "ubuntu/dists/$series->{'name'}/$component/binary-$arch->{'name'}/Packages.gz";
                my $response =
                  $self->ua->mirror($url, $self->_get_pkg_filename($series->{'name'}, $arch->{'name'}, $component));

                if ($response->is_error()) {
                    l "Cannot download $url: " . $response->status_line();
                    undef($component_statuses{$component});
                } else {
                    $component_statuses{$component} =
                      $response->code() == 200 ? 1 : $response->code() == 304 ? 0 : undef;
                }
            }

            next unless grep {$_} values(%component_statuses);    # Nothing to update

            my @packages;
            foreach my $component (keys(%component_statuses)) {
                my $gz = IO::Uncompress::Gunzip->new(
                    $self->_get_pkg_filename($series->{'name'}, $arch->{'name'}, $component));
                local $/ = "\n\n";
                while (<$gz>) {
                    chomp();
                    my %pkg = map {split(/\s*:\s*/, $_, 2)} grep {/:/} split("\n");
                    push(
                        @packages,
                        {
                            series_id => $series->{'id'},
                            arch_id   => $arch->{'id'},
                            name      => $pkg{'Package'},
                            version   => $pkg{'Version'},
                        }
                    );
                }
            }

            $self->db->transaction(
                sub {
                    my %db_pkgs = map {+"$_->{'name'}=$_->{'version'}" => TRUE} @{
                        $self->get_all(
                            fields     => [qw(name version)],
                            filter     => {arch_id => $arch->{'id'}, series_id => $series->{'id'}},
                            for_update => TRUE,
                        )
                      };

                    my @new_packages = grep {!exists($db_pkgs{"$_->{'name'}=$_->{'version'}"})} @packages;

                    $self->db->dist_package->delete(
                        $self->db->filter({arch_id => $arch->{'id'}, series_id => $series->{'id'}}));
                    $self->db->dist_package->add_multi(\@packages, replace => TRUE);

                    $self->package_build_wait_depends->added_new_packages($series->{'id'}, $arch->{'id'},
                        [map {$_->{'name'}} @new_packages]);
                }
            );
        }
    }
}

sub get_components {qw(main universe multiverse)}

sub ua {
    my ($self) = @_;

    $self->{'__UA__'} = LWP::UserAgent->new() unless defined($self->{'__UA__'});

    return $self->{'__UA__'};
}

sub _get_pkg_filename {
    my ($self, $series, $arch, $component) = @_;

    return "/tmp/${series}_${arch}_${component}_Packages.bz2";
}

TRUE;
