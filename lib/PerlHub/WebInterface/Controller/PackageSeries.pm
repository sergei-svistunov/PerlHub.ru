package PerlHub::WebInterface::Controller::PackageSeries;

use qbit;

use base qw(PerlHub::WebInterface::Controller);

__PACKAGE__->model_accessors(package_series => 'PerlHub::Application::Model::PackageSeries',);

sub list : CMD : DEFAULT {
    my ($self) = @_;

    return $self->denied() unless $self->check_rights('package_series_view');

    my $vo = $self->get_vopts(model => $self->package_series, per_page => 10);

    return $self->from_template(
        'package_series/list.tt2',
        vars => {
            page_header    => gettext('Series'),
            package_series => $self->package_series->get_all(
                fields => [qw(id name description)],
                $vo->get_model_opts(),
                order_by => [[id => TRUE]],
            ),
            $vo->get_template_vars(),
        }
    );
}

sub add : FORMCMD {
    my ($self) = @_;

    return (
        check_rights => ['package_series_add'],

        description => gettext('Add new'),

        fields => [
            {name => 'name',        type => 'input', label => gettext('Name'),        trim => TRUE, required => TRUE},
            {name => 'description', type => 'input', label => gettext('Description'), trim => TRUE, required => TRUE},
            {type => 'submit', value => pgettext('package_series', 'Add')}
        ],

        save => sub {
            my ($form) = @_;

            $self->package_series->add(map {$_ => $form->get_value($_)} qw(name description));
        },

        redirect => 'list',
    );
}

TRUE;
