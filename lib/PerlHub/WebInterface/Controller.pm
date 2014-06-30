package PerlHub::WebInterface::Controller::_VO;

use qbit;

use base qw(QBit::Class);

use POSIX qw(ceil);

__PACKAGE__->mk_ro_accessors(qw(controller model));

sub init {
    my ($self) = @_;

    $self->{'per_page'} ||= 20;
    $self->{'page'} = $self->controller->request->param('page', 1);
}

sub get_model_opts {
    my ($self) = @_;

    return (
        calc_rows => TRUE,
        offset    => ($self->{'page'} - 1) * $self->{'per_page'},
        limit     => $self->{'per_page'}
    );
}

sub get_template_vars {
    my ($self) = @_;

    return (
        vopts => {
            page        => $self->{'page'},
            total_pages => ceil($self->model->found_rows() / $self->{'per_page'})
        }
    );
}

package PerlHub::WebInterface::Controller;

use qbit;

use base qw(QBit::WebInterface::Controller);

sub error {
    my ($self, $error) = @_;

    return $self->from_template('error.tt2', vars => {page_header => gettext('Error'), error => $error});
}

sub get_vopts {
    my ($self, %opts) = @_;

    return PerlHub::WebInterface::Controller::_VO->new(%opts, controller => $self);
}

TRUE;
