package PerlHub::Application::Model::DB::Package;

use qbit;

use base qw(QBit::Application::Model::DB::mysql);

__PACKAGE__->meta(
    tables => {
        package_arch => {
            fields => [
                {name => 'id',          type => 'TINYINT', unsigned => TRUE, not_null => TRUE, autoincrement => TRUE},
                {name => 'name',        type => 'VARCHAR', length   => 5,    not_null => TRUE},
                {name => 'description', type => 'VARCHAR', length   => 255,  not_null => TRUE},
            ],
            primary_key => ['id'],
        },

        package_series => {
            fields => [
                {name => 'id',          type => 'TINYINT', unsigned => TRUE, not_null => TRUE, autoincrement => TRUE},
                {name => 'name',        type => 'VARCHAR', length   => 20,   not_null => TRUE},
                {name => 'description', type => 'VARCHAR', length   => 255,  not_null => TRUE},
                {name => 'outdated',    type => 'BOOLEAN', not_null => TRUE, default  => 0},
            ],
            primary_key => ['id'],
            indexes     => [{fields => [qw(name)], unique => TRUE}],
        },

        package_source => {
            fields => [
                {name => 'id',        type => 'INT',      unsigned => TRUE, not_null => TRUE, autoincrement => TRUE},
                {name => 'name',      type => 'VARCHAR',  length   => 255,  not_null => TRUE},
                {name => 'version',   type => 'VARCHAR',  length   => 64,   not_null => TRUE},
                {name => 'upload_dt', type => 'DATETIME', not_null => TRUE},
                {name => 'user_id'},
                {name => 'build_depends', type => 'TEXT'}
            ],
            primary_key  => ['id'],
            foreign_keys => [[['user_id'] => 'users' => ['id']]],
            indexes      => [{fields => [qw(name version)], unique => TRUE}, {fields => ['upload_dt']}]
        },

        package_build => {
            fields => [
                {name => 'source_id'},
                {name => 'series_id'},
                {name => 'arch_id'},
                {name => 'multistate', type => 'BIGINT', unsigned => TRUE, not_null => TRUE, default => 0},
                {name => 'build_log', type => 'MEDIUMTEXT'},
            ],
            primary_key  => [qw(source_id series_id arch_id)],
            foreign_keys => [
                [['source_id'] => package_source => ['id']],
                [['arch_id']   => package_arch   => ['id']],
                [['series_id'] => package_series => ['id']]
            ],
            indexes => [{fields => ['multistate']}]
        },

        package_build_wait_depends => {
            fields => [
                {name => 'name', type => 'VARCHAR', length => 255, not_null => TRUE},
                {name => 'source_id'},
                {name => 'series_id'},
                {name => 'arch_id'},
            ],
            primary_key  => [qw(name series_id arch_id source_id)],
            foreign_keys => [[[qw(source_id series_id arch_id)] => package_build => [qw(source_id series_id arch_id)]]],
        },

        dist_package => {
            fields => [
                {name => 'series_id'},
                {name => 'arch_id'},
                {name => 'name', type => 'VARCHAR', length => 255, not_null => TRUE},
                {name => 'version', type => 'VARCHAR', length => 64, not_null => TRUE},
            ],
            primary_key  => [qw(series_id arch_id name version)],
            foreign_keys => [[['arch_id'] => package_arch => ['id']], [['series_id'] => package_series => ['id']]],
          }

    }
);

TRUE;
