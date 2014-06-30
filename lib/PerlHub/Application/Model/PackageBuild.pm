package PerlHub::Application::Model::PackageBuild;

use qbit;

use base qw(QBit::Application::Model::DBManager QBit::Application::Model::Multistate::DB);

use File::Path qw(make_path);

__PACKAGE__->model_accessors(
    db             => 'PerlHub::Application::Model::DB',
    package_source => 'PerlHub::Application::Model::PackageSource'
);

__PACKAGE__->register_rights(
    [
        {
            name        => 'package_build',
            description => sub {gettext('Rights for package builds')},
            rights      => {view_build_log => d_gettext('Right to view build log')},
        }
    ]
);

__PACKAGE__->model_fields(
    source_id       => {pk => TRUE, db           => TRUE},
    series_id       => {pk => TRUE, db           => TRUE},
    arch_id         => {pk => TRUE, db           => TRUE},
    multistate      => {db => TRUE},
    build_log       => {db => TRUE, check_rights => 'view_build_log'},
    multistate_name => {
        depends_on => 'multistate',
        get        => sub {
            $_[0]->model->get_multistate_name($_[1]->{'multistate'});
        },
    },
    series_name => {
        depends_on => 'series_id',
        get        => sub {
            $_[0]->{'series'}->{$_[1]->{'series_id'}};
        },
    },
    arch_name => {
        depends_on => 'arch_id',
        get        => sub {
            $_[0]->{'arches'}->{$_[1]->{'arch_id'}};
        },
    },
    package_name => {
        depends_on => 'source_id',
        get        => sub {
            $_[0]->{'sources'}->{$_[1]->{'source_id'}}{'name'};
        },
    },
    package_version => {
        depends_on => 'source_id',
        get        => sub {
            $_[0]->{'sources'}->{$_[1]->{'source_id'}}{'version'};
        },
    }
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        source_id  => {type => 'number',     label => d_gettext('Source ID')},
        series_id  => {type => 'number',     label => d_gettext('Series ID')},
        arch_id    => {type => 'number',     label => d_gettext('Architecture ID')},
        multistate => {type => 'multistate', label => d_gettext('Multistate')},
    }
);

__PACKAGE__->multistates_graph(
    empty_name => d_gettext('New'),
    multistates =>
      [[building => d_gettext('Building')], [completed => d_gettext('Completed')], [failed => d_gettext('Failed')]],
    actions => {
        start_building     => d_gettext('Start building'),
        building_completed => d_gettext('Building completed'),
        building_failed    => d_gettext('Building failed')
    },
    multistate_actions => [
        {
            action    => 'start_building',
            from      => '__EMPTY__',
            set_flags => ['building'],
        },
        {
            action      => 'building_completed',
            from        => 'building',
            set_flags   => ['completed'],
            reset_flags => ['building'],
        },
        {
            action      => 'building_failed',
            from        => 'building',
            set_flags   => ['failed'],
            reset_flags => ['building'],
        },
    ]
);

sub pre_process_fields {
    my ($self, $fields, $result) = @_;

    $fields->{'series'} = {
        map {$_->{'id'} => $_->{'name'}} @{
            $self->db->package_series->get_all(
                fields => [qw(id name)],
                filter => {id => array_uniq(map {$_->{'series_id'}} @$result)}
            )
          }
      }
      if $fields->need('series_name');

    $fields->{'arches'} = {
        map {$_->{'id'} => $_->{'name'}} @{
            $self->db->package_arch->get_all(
                fields => [qw(id name)],
                filter => {id => array_uniq(map {$_->{'arch_id'}} @$result)}
            )
          }
      }
      if $fields->need('arch_name');

    if (grep {$fields->need($_)} qw(package_name package_version)) {
        $fields->{'sources'} = {
            map {delete($_->{'id'}) => $_} @{
                $self->package_source->get_all(
                    fields => [
                        'id',
                        ($fields->need('package_name')    ? ('name')    : ()),
                        ($fields->need('package_version') ? ('version') : ()),
                    ],
                    filter => {id => array_uniq(map {$_->{'source_id'}} @$result)}
                )
              }
        };
    }
}

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->package_build,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add {
    my ($self, %opts) = @_;

    my @missed_req_fields = grep {!defined($opts{$_})} qw(source_id series_id arch_id);
    throw Exception::BadArguments ngettext(
        'Missed required field "%s"',
        'Missed required fields "%s"',
        scalar(@missed_req_fields),
        join(', ', @missed_req_fields)
    ) if @missed_req_fields;

    return $self->db->package_build->add({hash_transform(\%opts, [qw(source_id series_id arch_id)])});
}

sub take_build {
    my ($self) = @_;

    my $build_id;

    $self->db->transaction(
        sub {
            $build_id = $self->db->package_build->get_all(
                fields     => [qw(source_id series_id arch_id)],
                filter     => {multistate => $self->get_multistate_by_action('start_building')},
                order_by   => [['source_id']],
                limit      => 1,
                for_update => TRUE,
            )->[0] // return undef;

            $self->do_action($build_id, 'start_building');
        }
    );

    return undef unless $build_id;

    my $build = $self->get($build_id, fields => [qw(source_id series_name arch_name package_name package_version)])
      // return undef;

    my $source_store_dir =
      $self->get_option('source_store_dir') . "/$build->{'package_name'}_$build->{'package_version'}";

    opendir(my $dh, $source_store_dir)
      || throw gettext('Cannot open dir "%s": %s', $source_store_dir, Encode::decode_utf8($!));
    my ($arc_name) = grep {/\.(?:tar\.|t)(?:gz|bz|bz2)$/} readdir($dh);
    closedir($dh);

    $build->{'source_arc_url'} =
      $self->get_option('sources_uri') . "/$build->{'package_name'}_$build->{'package_version'}/$arc_name";

    return $build;
}

sub get_series_bulded_cnt {
    my ($self) = @_;

    my $data = $self->db->query->select(
        table  => $self->db->package_build,
        fields => {
            series_id => '',
            cnt       => {count => ['source_id']}
        },
        filter => [multistate => 'IN' => \$self->get_multistates_by_filter('completed')]
    )->group_by('series_id')->get_all();

    return {map {$_->{'series_id'} => $_->{'cnt'}} @$data};
}

sub on_action_start_building {
    my ($self, $obj) = @_;

    $self->db->package_build->edit($obj, {build_log => ''});
}

sub on_action_building_completed {
    my ($self, $obj, %opts) = @_;

    my $series = $self->db->package_series->get($obj->{'series_id'}, fields => ['name'])->{'name'};

    my $incomming_dir = $self->get_option('binaries_incomming_path') . "/$series";
    make_path($incomming_dir) unless -d $incomming_dir;

    writefile("$incomming_dir/$_", $opts{'files'}->{$_}, binary => TRUE) foreach keys(%{$opts{'files'}});

    $self->db->package_build->edit($obj, {build_log => $opts{'build_log'}});
}

sub on_action_building_failed {
    my ($self, $obj, %opts) = @_;

    $self->db->package_build->edit($obj, {build_log => $opts{'build_log'}});
}

sub _multistate_db_table {$_[0]->db->package_build}
# ToDo: Add it
#sub _action_log_db_table {$_[0]->db->package_build_action_log}

TRUE;
