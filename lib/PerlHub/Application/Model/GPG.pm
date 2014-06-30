package Exception::GPG;
use base qw(Exception);

package Exception::GPG::Run;
use base qw(Exception::GPG);

package PerlHub::Application::Model::GPG;

use qbit;

use base qw(QBit::Application::Model::DBManager);

use IPC::Run qw(run);
use File::Path qw(make_path);
use File::Temp qw(tempfile);

__PACKAGE__->register_rights(
    [
        {
            name        => 'gpg',
            description => sub {gettext('Rights for GPG')},
            rights      => {gpg_manage_public_keys => d_gettext('Right to manage GPG public keys')},
        }
    ]
);

__PACKAGE__->model_accessors(db => 'PerlHub::Application::Model::DB::User');

__PACKAGE__->model_fields(
    id      => {db => TRUE, pk => TRUE},
    sign    => {db => TRUE, pk => TRUE},
    user_id => {db => TRUE},
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        id      => {type => 'text',   label => d_gettext('ID')},
        sign    => {type => 'text',   label => d_gettext('Sign')},
        user_id => {type => 'number', label => d_gettext('User ID')},
    }
);

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->gpg_keys,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add_public_key {
    my ($self, $key, %opts) = @_;

    throw Exception::Denied unless $self->check_rights('gpg_manage_public_keys');

    my $gpg_home = $self->get_option('gpg_dir');
    make_path($gpg_home) unless -d $gpg_home;

    my ($fh, $filename) = tempfile();
    print $fh $key;
    close($fh);

    my ($out, $err) = $self->_gpg('--homedir' => $self->get_option('gpg_dir'), '--import' => $filename);

    unlink($filename);

    my ($id, $sign);
    if ($out =~ /[^\s]+\s+IMPORTED\s+([0-9A-F]+)\s+([^\r\n]+)/s) {
        ($id, $sign) = ($1, $2);
        $self->db->gpg_keys->add(
            {
                user_id => $self->get_option('cur_user')->{'id'},
                id      => $id,
                sign    => $sign,
            }
        );
    } else {
        throw Exception::GPG gettext('Key is already imported');
    }

    return ($id, $sign);
}

sub verify {
    my ($self, $filename) = @_;

    my $res;
    try {
        my ($out, $err) = $self->_gpg('--homedir' => $self->get_option('gpg_dir'), '--verify' => $filename);
        $res = [$1, $2] if $out =~ /[^\s]+\s+GOODSIG\s+([0-9A-F]+)\s+([^\r\n]+)/s;
    }
    catch Exception::GPG::Run with {};

    return $res;
}

sub sign {
    my ($self, $filename) = @_;

    my $gpg_home = $self->get_option('sign_gpg_dir') // return FALSE;
    return FALSE unless -d $gpg_home;

    my ($out, $err) = $self->_gpg(
        '--homedir' => $gpg_home,
        '--armor',
        '--output'      => "$filename.gpg",
        '--detach-sign' => $filename
    );

    return $out =~ /SIG_CREATED/;
}

sub get_sign_pub_key {
    my ($self) = @_;

    my $gpg_home = $self->get_option('sign_gpg_dir') // return FALSE;
    return FALSE unless -d $gpg_home;

    my ($out, $err) = $self->_gpg(
        '--homedir' => $gpg_home,
        '--list-public-keys'
    );

    return [$out =~ /pub[^\/]+\/([^\s]+)\s/]->[0];
}

sub _gpg {
    my ($self, @params) = @_;

    my ($in, $out, $err) = ('', '', '');
    unless (
        run(
            [
                '/usr/bin/gpg' => (
                    '--no-tty', '--lock-multiple', '--no-secmem-warning', '--no-permission-warning', '--yes',
                    '--keyid-format' => 'long',
                    '--status-fd'    => 1,
                    '--command-fd'   => 0,
                    @params
                )
            ],
            \$in,
            \$out,
            \$err
           )
      )
    {
        my ($error_text) = $err =~ /^gpg: (.+)$/m;
        throw Exception::GPG::Run $error_text;
    }

    return ($out, $err);
}

TRUE;
