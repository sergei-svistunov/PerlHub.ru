package PerlHub::Application::Model::Users;

use qbit;

use base qw(QBit::Application::Model::DBManager);

use Digest::SHA qw(sha512_hex);

__PACKAGE__->model_accessors(db => 'PerlHub::Application::Model::DB');

__PACKAGE__->model_fields(
    id       => {db => TRUE, pk      => TRUE, default => TRUE},
    login    => {db => TRUE, default => TRUE},
    password => {db => TRUE},
    email => {db => TRUE, default => TRUE},
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        id       => {type => 'number'},
        login    => {type => 'text'},
        password => {type => 'text'},
        email    => {type => 'text'},
    }
);

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->users,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add {
    my ($self, %opts) = @_;

    my @missed_required_fields = grep {!defined($opts{$_})} qw(login password email);
    throw Exception::BadArguments ngettext(
        'Missed required parameter "%s"',
        'Missed required parameters: %s',
        scalar(@missed_required_fields),
        join(', ', @missed_required_fields)
    ) if @missed_required_fields;

    my $user_id;
    try {
        $user_id = $self->db->users->add(
            {
                password => $self->password_hash($opts{'login'}, $opts{'password'}),
                map {($_ => $opts{$_})} qw(login email)
            }
        );
    }
    catch Exception::DB::DuplicateEntry with {
        throw Exception::BadArguments gettext('User with login "%s" is already exists', $opts{'login'});
    };

    return $user_id;
}

sub get_by_login {
    my ($self, $login, %opts) = @_;

    return $self->get_all(%opts, filter => {login => $login}, limit => 1)->[0];
}

sub check_auth {
    my ($self, $login, $password) = @_;

    my $user = $self->get_by_login($login, fields => ['password']) || return FALSE;

    return $self->password_hash($login, $password) eq $user->{'password'}
      ? $self->session_hash($login, $user->{'password'})
      : FALSE;
}

sub check_session {
    my ($self, $login, $session_hash) = @_;

    utf8::encode($login);
    utf8::encode($session_hash);

    my $user = $self->get_by_login($login, fields => ['password']) || return FALSE;

    return $session_hash eq $self->session_hash($login, $user->{'password'});
}

sub session_hash {
    my ($self, $login, $password_hash) = @_;

    utf8::encode($login);
    utf8::encode($password_hash);

    return sha512_hex($login . $password_hash . sha512_hex($self->get_option('salt', '')));
}

sub password_hash {
    my ($self, $login, $password) = @_;

    utf8::encode($login);
    utf8::encode($password);

    return sha512_hex($password . sha512_hex($login . $self->get_option('salt', '')));
}

TRUE;
