package PerlHub::WebInterface::Controller::User;

use qbit;

use base qw(PerlHub::WebInterface::Controller);

__PACKAGE__->model_accessors(users => 'PerlHub::Application::Model::Users', gpg => 'PerlHub::Application::Model::GPG');

sub register : FORMCMD {
    my ($self) = @_;

    return (
        fields => [
            {
                name       => 'login',
                type       => 'input',
                label      => pgettext('Noun', 'Login'),
                max_length => 64,
                trim       => TRUE,
                required   => TRUE,
                check      => sub {
                    my ($field, $value) = @_;
                    throw Exception::Form gettext('Reserved name')
                      if in_array($value, [qw(admin administrator root daemon support bin sys backup nobody mail)]);
                  }
            },
            {name => 'password',  type => 'password', label => gettext('Password'),        required => TRUE},
            {name => 'password2', type => 'password', label => gettext('Retype password'), required => TRUE},
            {name => 'email', type => 'email', label => gettext('E-Mail'), trim => TRUE, required => TRUE},
            {name => 'captcha', type  => 'reCAPTCHA'},
            {type => 'submit',  value => gettext('Save')}
        ],

        check => sub {
            my ($form) = @_;

            throw Exception::Form gettext('Passwords are not equals')
              if $form->get_value('password') ne $form->get_value('password2');
        },

        save => sub {
            my ($form) = @_;

            $self->users->add(map {$_ => $form->get_value($_)} qw(login password email));

            my $digest = $self->users->check_auth($form->get_value('login'), $form->get_value('password'));

            $self->response->add_cookie(
                qs      => [$form->get_value('login') => $digest],
                expires => '+30d',
            );
        },

        redirect => 'profile',
    );
}

sub login : FORMCMD {
    my ($self) = @_;

    return (
        fields => [
            (
                $self->request->param('retpath')
                ? {name => 'retpath', type => 'hidden', value => $self->request->param('retpath')}
                : ()
            ),
            {name => 'login',    type => 'input',    label => gettext('Login'),    trim     => TRUE, required => TRUE},
            {name => 'password', type => 'password', label => gettext('Password'), required => TRUE},
            {type => 'submit', value => pgettext('Verb', 'Login')}
        ],

        save => sub {
            my ($form) = @_;

            my $digest = $self->users->check_auth($form->get_value('login'), $form->get_value('password'))
              || throw Exception::Form gettext('Invalid login/password');

            $self->response->add_cookie(
                qs      => [$form->get_value('login') => $digest],
                expires => '+30d',
            );
        },

        redirect => 'profile',
    );
}

sub logout : CMD {
    my ($self) = @_;

    $self->response->add_cookie(
        qs      => '',
        expires => '-1y',
    );

    return $self->redirect2url('/');
}

sub profile : FORMCMD {
    my ($self) = @_;

    return $self->denied() unless $self->get_option('cur_user');

    my $user = $self->users->get_by_login($self->get_option('cur_user', {})->{'login'}, fields => [qw(id email)])
      // return $self->denied();

    return (
        fields => [
            {
                name     => 'email',
                type     => 'email',
                label    => gettext('E-Mail'),
                value    => $user->{'email'},
                trim     => TRUE,
                required => TRUE
            },
            {type => 'submit', value => gettext('Save')}
        ],

        save => sub {
            my ($form) = @_;

            $self->users->edit($user->{'id'}, {map {$_ => $form->get_value($_)} qw(email)}) if $user;
        },
    );
}

sub gpg_keys : CMD {
    my ($self) = @_;

    return $self->denied() unless $self->check_rights('gpg_manage_public_keys');

    return $self->from_template(
        'user/gpg_keys.tt2',
        vars => {
            page_header => gettext('Your GPG keys'),
            gpg_keys    => $self->gpg->get_all(
                fields => [qw(id sign)],
                filter => {user_id => $self->get_option('cur_user')->{'id'}}
            )
        }
    );
}

sub upload_gpg_key : CMD : SAFE {
    my ($self) = @_;

    return $self->denied() unless $self->check_rights('gpg_manage_public_keys');

    my $error;
    try {
        $self->gpg->add_public_key($self->request->param('key'));
    }
    catch Exception::GPG with {
        $error = shift->message();
    };

    return defined($error) ? $self->error($error) : $self->redirect('gpg_keys');
}

TRUE;
