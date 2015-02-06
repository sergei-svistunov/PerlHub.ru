package PerlHub::Application::Model::PackageBuildWaitDepends;

use qbit;

use base qw(QBit::Application::Model::DBManager);

__PACKAGE__->model_accessors(db => 'PerlHub::Application::Model::DB',);

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

TRUE;
