package PerlHub::Application::Model::PackageBuildWaitDepends;

use qbit;

use base qw(QBit::Application::Model::DBManager);

__PACKAGE__->model_accessors(
    db            => 'PerlHub::Application::Model::DB::Package',
    package_build => 'PerlHub::Application::Model::PackageBuild',
);

__PACKAGE__->model_fields(
    name      => {pk => TRUE, db => TRUE},
    source_id => {pk => TRUE, db => TRUE},
    series_id => {pk => TRUE, db => TRUE},
    arch_id   => {pk => TRUE, db => TRUE},
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        name      => {type => 'text',   label => d_gettext('Package name')},
        source_id => {type => 'number', label => d_gettext('Source ID')},
        series_id => {type => 'number', label => d_gettext('Series ID')},
        arch_id   => {type => 'number', label => d_gettext('Architecture ID')},
    }
);

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->package_build_wait_depends,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add {
    my ($self, %opts) = @_;

    my @missed_req_fields = grep {!defined($opts{$_})} qw(name source_id series_id arch_id);
    throw Exception::BadArguments ngettext(
        'Missed required field "%s"',
        'Missed required fields "%s"',
        scalar(@missed_req_fields),
        join(', ', @missed_req_fields)
    ) if @missed_req_fields;

    return $self->db->package_build_wait_depends->add({hash_transform(\%opts, [qw(name source_id series_id arch_id)])});
}

sub added_new_packages {
    my ($self, $series, $arch, $packages) = @_;

    $self->db->transaction(
        sub {
            my $build_packages = $self->db->package_build_wait_depends->get_all(
                fields => [qw(source_id series_id arch_id)],
                filter => {
                    series_id => $series,
                    (arch_id => $arch == 1 || $arch == 3 ? [1, 3] : $arch),
                    name => $packages
                },
                distinct   => TRUE,
                for_update => TRUE,
            );

            return unless @$build_packages;

            $self->db->package_build_wait_depends->delete(
                $self->db->filter(
                    {
                        series_id => $series,
                        (arch_id => $arch == 1 || $arch == 3 ? [1, 3] : $arch),
                        name => $packages
                    }
                )
            );

            foreach my $pkg (@$build_packages) {
                $self->package_build->do_action($pkg, 'depends_changed')
                  unless $self->db->package_build_wait_depends->get_all(
                    fields => ['source_id'],
                    filter => {
                        source_id => $pkg->{'source_id'},
                        series_id => $pkg->{'series_id'},
                        arch_id   => $pkg->{'arch_id'},
                    },
                    limit => 1,
                  )->[0];
            }
        }
    );
}

TRUE;
