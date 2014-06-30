package PerlHub::WebInterface::Controller::Package;

use qbit;

use base qw(PerlHub::WebInterface::Controller);

__PACKAGE__->model_accessors(
    package_source => 'PerlHub::Application::Model::PackageSource',
    package_build  => 'PerlHub::Application::Model::PackageBuild'
);

sub list : CMD : DEFAULT {
    my ($self) = @_;

    my $vo = $self->get_vopts(model => $self->package_source, per_page => 10);

    my @filter;
    push(@filter, [name => LIKE => $self->request->param('filter_pkg_name')])
      if $self->request->param('filter_pkg_name');

    return $self->from_template(
        'package/list.tt2',
        vars => {
            page_header => gettext('Uploaded source packages'),
            packages    => $self->package_source->get_all(
                fields => [qw(id name version upload_dt builds)],
                $vo->get_model_opts(),
                (@filter ? (filter => [AND => \@filter]) : ()),
                order_by => [[upload_dt => TRUE]],
            ),
            $vo->get_template_vars(),
        }
    );
}

sub build_log : CMD {
    my ($self) = @_;

    return $self->denied() unless $self->check_rights('view_build_log');

    my $build = $self->package_build->get(
        {
            source_id => $self->request->param('id'),
            series_id => $self->request->param('series_id'),
            arch_id   => $self->request->param('arch_id')
        },
        fields => ['build_log']
    ) // return $self->response->status(404);

    return $self->from_template(\'<pre>[% log | html %]</pre>', no_hf => TRUE, vars => {log => $build->{'build_log'}});
}

TRUE;
