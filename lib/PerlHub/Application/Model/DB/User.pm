package PerlHub::Application::Model::DB::User;

use qbit;

use base qw(QBit::Application::Model::DB::mysql);

__PACKAGE__->meta(
    tables => {
        users => {
            fields => [
                {name => 'id',       type => 'INT',     unsigned => TRUE, not_null => TRUE, autoincrement => TRUE},
                {name => 'login',    type => 'VARCHAR', length   => 64,   not_null => TRUE},
                {name => 'password', type => 'VARCHAR', length   => 128,  not_null => TRUE},
                {name => 'email',    type => 'VARCHAR', length   => 512,  not_null => TRUE},
            ],
            primary_key => ['id'],
            indexes     => [{fields => ['login'], unique => TRUE}]
        },

        gpg_keys => {
            fields => [
                {name => 'id',   type => 'CHAR',    length => 16,  not_null => TRUE},
                {name => 'sign', type => 'VARCHAR', length => 255, not_null => TRUE},
                {name => 'user_id'},
            ],
            primary_key  => [qw(id sign)],
            foreign_keys => [[['user_id'] => 'users' => ['id']]],
            indexes => [{fields => [qw(id sign)]}]
        },
    }
);

TRUE;
