package PerlHub::Application::Model::PackageBuild;

use qbit;

use base qw(QBit::Application::Model::DBManager QBit::Application::Model::Multistate::DB);

use File::Path qw(make_path);
use Dpkg::Deps;

__PACKAGE__->model_accessors(
    db                         => 'PerlHub::Application::Model::DB::Package',
    package_source             => 'PerlHub::Application::Model::PackageSource',
    dist_package               => 'PerlHub::Application::Model::DistPackage',
    package_build_wait_depends => 'PerlHub::Application::Model::PackageBuildWaitDepends',
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
    },
    build_depends => {
        depends_on => 'source_id',
        get        => sub {
            $_[0]->{'sources'}->{$_[1]->{'source_id'}}{'build_depends'};
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
        source =>
          {type => 'subfilter', model_accessor => 'package_source', field => 'source_id', label => d_gettext('Source')}
    }
);

__PACKAGE__->multistates_graph(
    empty_name  => d_gettext('New'),
    multistates => [
        [building     => d_gettext('Building')],
        [completed    => d_gettext('Completed')],
        [failed       => d_gettext('Failed')],
        [need_depends => d_gettext('Need depends')],
        [published    => d_gettext('Published')],
    ],
    actions => {
        start_building       => d_gettext('Start building'),
        building_completed   => d_gettext('Building completed'),
        building_failed      => d_gettext('Building failed'),
        publish              => d_gettext('Publish'),
        build_depends_failed => d_gettext('Build depends is not ready'),
        depends_changed      => d_gettext('Depends changed'),
    },
    multistate_actions => [
        {
            action    => 'start_building',
            from      => '__EMPTY__',
            set_flags => ['building'],
        },
        {
            action      => 'build_depends_failed',
            from        => 'building',
            set_flags   => ['need_depends'],
            reset_flags => ['building'],
        },
        {
            action      => 'depends_changed',
            from        => 'need_depends',
            reset_flags => ['need_depends'],
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
        {
            action      => 'publish',
            from        => 'completed',
            set_flags   => ['published'],
            reset_flags => ['completed'],
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

    if (grep {$fields->need($_)} qw(package_name package_version build_depends)) {
        $fields->{'sources'} = {
            map {delete($_->{'id'}) => $_} @{
                $self->package_source->get_all(
                    fields => [
                        'id',
                        ($fields->need('package_name')    ? ('name')          : ()),
                        ($fields->need('package_version') ? ('version')       : ()),
                        ($fields->need('build_depends')   ? ('build_depends') : ()),
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

    my $build =
      $self->get($build_id,
        fields => [qw(source_id series_id series_name arch_id arch_name package_name package_version build_depends)])
      // return undef;

    my $deps = deps_parse($build->{'build_depends'}, host_arch => $build->{'arch_name'});

    my $facts = Dpkg::Deps::KnownFacts->new();
    $facts->add_installed_package($_->{'name'}, $_->{'version'}, $build->{'arch_name'}, TRUE) foreach @{
        $self->dist_package->get_all(
            fields => [qw(name version)],
            filter => {
                series_id => $build->{'series_id'},
                arch_id   => ($build->{'arch_id'} == 1 ? 3 : $build->{'arch_id'})
            }
        )
      };

    $facts->add_installed_package($_->{'package_name'}, $_->{'package_version'}, $build->{'arch_name'}, TRUE) foreach @{
        $self->get_all(
            fields => [qw(package_name package_version)],
            filter => {
                series_id  => $build->{'series_id'},
                arch_id    => [1, $build->{'arch_id'} == 1 ? 3 : $build->{'arch_id'}],
                multistate => 'published',
            }
          )
      };

    $deps->simplify_deps($facts);
    unless ($deps->is_empty()) {
        $self->do_action($build_id, 'build_depends_failed', missed_deps => [map {$_->{'package'}} $deps->get_deps()]);
        return undef;
    }

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

sub on_action_build_depends_failed {
    my ($self, $obj, %opts) = @_;

    $self->package_build_wait_depends->add(name => $_, (map {$_ => $obj->{$_}} qw(source_id series_id arch_id)))
      foreach @{$opts{'missed_deps'}};
}

sub on_action_publish {
    my ($self, $obj) = @_;

    $self->package_build_wait_depends->added_new_packages($obj->{'series_id'}, $obj->{'arch_id'},
        [$self->get($obj, fields => ['package_name'])->{'package_name'}]);
}

sub _multistate_db_table {$_[0]->db->package_build}
# ToDo: Add it
#sub _action_log_db_table {$_[0]->db->package_build_action_log}

TRUE;
