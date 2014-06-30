package PerlHub::WebInterface::Controller::API;

use qbit;

use base qw(QBit::WebInterface::Controller);

__PACKAGE__->model_accessors(
    package_build => 'PerlHub::Application::Model::PackageBuild',
    db            => 'PerlHub::Application::Model::DB',             # ToDo: kill it
);

sub get_builder_settings : CMD {
    my ($self) = @_;

    return $self->as_json(
        {
            arches       => [map {$_->{'name'}} @{$self->db->package_arch->get_all(fields   => [qw(name)])}],
            series       => [map {$_->{'name'}} @{$self->db->package_series->get_all(fields => [qw(name)])}],
            othermirrors => [
                'deb http://packages.perlhub.ru {{SERIES}}/all/',
                'deb http://packages.perlhub.ru {{SERIES}}/{{ARCH}}/',
                #'deb http://ppa.launchpad.net/qbit-perl/{{SERIES}}/ubuntu {{SERIES}} main',
            ],
            components => [qw(main universe multiverse)],
        }
    );
}

sub get_build_task : CMD {
    my ($self) = @_;

    return $self->as_json($self->package_build->take_build());
}

sub complete_build_task : CMD {
    my ($self) = @_;

    # ToDo: ugly
    my %arches =
      map {$_->{'name'} => $_->{'id'}} @{$self->db->package_arch->get_all(fields => [qw(id name)])};
    my %series =
      map {$_->{'name'} => $_->{'id'}} @{$self->db->package_series->get_all(fields => [qw(id name)])};

    my $error;
    try {
        $self->package_build->do_action(
            {
                source_id => $self->request->param('source_id'),
                arch_id   => $arches{$self->request->param('arch_name')},
                series_id => $series{$self->request->param('series_name')}
            },
            'building_completed',
            files => {map {$_->{'filename'} => $_->{'content'}} @{$self->request->param_array('file')}},
            build_log => $self->request->param('build_log'),
        );
    }
    catch {
        $error = shift->message();
    };

    return $self->as_text($error // 'OK');
}

sub fail_build_task : CMD {
    my ($self) = @_;

    # ToDo: ugly
    my %arches =
      map {$_->{'name'} => $_->{'id'}} @{$self->db->package_arch->get_all(fields => [qw(id name)])};
    my %series =
      map {$_->{'name'} => $_->{'id'}} @{$self->db->package_series->get_all(fields => [qw(id name)])};

    my $error;
    try {
        $self->package_build->do_action(
            {
                source_id => $self->request->param('source_id'),
                arch_id   => $arches{$self->request->param('arch_name')},
                series_id => $series{$self->request->param('series_name')}
            },
            'building_failed',
            build_log => $self->request->param('build_log'),
        );
    }
    catch {
        $error = shift->message();
    };

    return $self->as_text($error // 'OK');
}

TRUE;
