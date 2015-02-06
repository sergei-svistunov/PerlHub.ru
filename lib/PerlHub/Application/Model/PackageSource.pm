package PerlHub::Application::Model::PackageSource;

use qbit;

use base qw(QBit::Application::Model::DBManager);

use Dpkg::Control;
use Dpkg::Checksums;
use File::Basename;
use File::Copy;
use File::Path qw(make_path);
use version;

__PACKAGE__->model_accessors(
    db            => 'PerlHub::Application::Model::DB',
    package_build => 'PerlHub::Application::Model::PackageBuild',
    gpg           => 'PerlHub::Application::Model::GPG',
    sendmail      => 'QBit::Application::Model::SendMail',
);

__PACKAGE__->model_fields(
    id            => {pk => TRUE, db => TRUE},
    name          => {db => TRUE},
    version       => {db => TRUE},
    upload_dt     => {db => TRUE},
    build_depends => {db => TRUE},
    files         => {
        depends_on => 'id',
        get        => sub {
            $_[0]->{'files'}->{$_[1]->{'id'}};
        },
    },
    builds => {
        depends_on => 'id',
        get        => sub {
            $_[0]->{'builds'}->{$_[1]->{'id'}};
          }
    }
);

__PACKAGE__->model_filter(
    db_accessor => 'db',
    fields      => {
        id   => {type => 'number', label => d_gettext('Source ID')},
        name => {type => 'text',   label => d_gettext('Name')},
    }
);

sub pre_process_fields {
    my ($self, $fields, $result) = @_;

    if ($fields->need('files')) {
        foreach my $source_files (
            @{
                $self->db->package_source_files->get_all(
                    fields => [qw(id dsc_name dsc_content changes_name changes_content source_name source_content)],
                    filter => {id => array_uniq(map {$_->{'id'}} @$result)}
                )
            }
          )
        {
            $fields->{'files'}{$source_files->{'id'}}{$source_files->{"${_}_name"}} = $source_files->{"${_}_content"}
              foreach qw(dsc changes source);
        }
    }

    if ($fields->need('builds')) {
        foreach my $build (
            @{
                $self->package_build->get_all(
                    fields => [qw(source_id multistate multistate_name series_id arch_id series_name arch_name)],
                    filter => {source_id => array_uniq(map {$_->{'id'}} @$result)}
                )
            }
          )
        {
            $fields->{'builds'}{$build->{'source_id'}} //= [];
            push(@{$fields->{'builds'}{$build->{'source_id'}}}, $build);
        }
    }
}

sub query {
    my ($self, %opts) = @_;

    return $self->db->query->select(
        table  => $self->db->package_source,
        fields => $opts{'fields'}->get_db_fields(),
        filter => $opts{'filter'},
    );
}

sub add {
    my ($self, $changes_filename) = @_;

    my $source_store_dir = $self->get_option('source_store_dir');
    make_path($source_store_dir) unless -d $source_store_dir;

    my $changes = Dpkg::Control->new(type => CTRL_FILE_CHANGES);
    $changes->load($changes_filename);

    my $source_dir = dirname($changes_filename);
    my $pkg_id;

    try {
        my $owner = $self->gpg->verify($changes_filename)
          || throw Exception::BadArguments gettext('Invalid GPG sign for file "%s"', basename($changes_filename));

        $owner = $self->gpg->get({id => $owner->[0], sign => $owner->[1]}, fields => ['user_id'])
          || throw Exception::BadArguments gettext('Unknown user', basename($changes_filename));

        $owner = $owner->{'user_id'};

        throw Exception::BadArguments gettext('Package must have "source" architecture')
          if $changes->{'Architecture'} ne 'source';

        try {
            version->parse($changes->{'Version'});
        }
        catch {
            throw Exception::BadArguments gettext('Invalid version "%s": %s', $changes->{'Version'}, shift->message());
        };

        my %files = (changes => basename($changes_filename));

        foreach (split("\n", $changes->{'Files'})) {
            chomp();
            next unless $_;
            my @fields = split(' ');

            my $checksums = Dpkg::Checksums->new();
            my $fn        = "$source_dir/$fields[4]";
            $checksums->add_from_file($fn, checksums => ['md5']);

            throw Exception::BadArguments gettext('Invalid checksum for file "%s"', $fields[4])
              if $fields[1] != $checksums->get_size($fn) || $fields[0] ne $checksums->get_checksum($fn, 'md5');

            if ($fields[4] =~ /\.dsc$/) {
                $files{'dsc'} = $fields[4];
            } else {
                $files{'source'} = $fields[4];
            }
        }

        my $dsc = Dpkg::Control->new(type => CTRL_PKG_SRC);
        $dsc->load("$source_dir/$files{'dsc'}");

        my @series_ids =
          map {$_->{'id'}} @{$self->db->package_series->get_all(fields => ['id'], filter => {outdated => 0})};
        my %archs = map {$_->{'name'} => $_->{'id'}} @{$self->db->package_arch->get_all(fields => [qw(id name)])};

        $self->db->transaction(
            sub {
                try {
                    $pkg_id = $self->db->package_source->add(
                        {
                            name          => $changes->{'Source'},
                            version       => $changes->{'Version'},
                            upload_dt     => curdate(oformat => 'db_time'),
                            user_id       => $owner,
                            build_depends => join(', ', map {$dsc->{$_}} grep {/^Build-Depends/i} keys(%$dsc)),
                        }
                    );
                }
                catch Exception::DB::DuplicateEntry with {
                    throw Exception::BadArguments gettext('Source package "%s (%s)" was uploaded early',
                        $changes->{'Source'}, $changes->{'Version'});
                };

                my $package_store = "$source_store_dir/$changes->{'Source'}_$changes->{'Version'}";
                mkdir($package_store)
                  || throw gettext('Cannot create dir "%s": %s', $package_store, Encode::decode_utf8($!));

                foreach my $fn (values(%files)) {
                    move("$source_dir/$fn", "$package_store/$fn")
                      || throw gettext(
                        'Cannot move "%s" to "%s": %s', "$source_dir/$fn",
                        "$package_store/$fn",           Encode::decode_utf8($!)
                      );
                }

                my @arch_names = $dsc->{'Architecture'} eq 'any' ? qw(i386 amd64) : ($dsc->{'Architecture'});
                foreach my $arch (@arch_names) {
                    foreach my $series_id (@series_ids) {
                        $self->package_build->add(
                            source_id => $pkg_id,
                            series_id => $series_id,
                            arch_id   => (
                                $archs{$arch}
                                  // throw Exception::BadArguments gettext('Unknown architecture "%s"', $arch)
                            )
                        );
                    }
                }
            }
        );

        $self->sendmail->send(
            from    => 'noreply@perlhub.ru',
            to      => $changes->{'Changed-By'} // $changes->{'Maintainer'},
            subject => gettext('Package %s (%s) was ACCEPTED', $changes->{'Source'}, $changes->{'Version'}),
            body    => gettext(
                'Package %s (%s) will try build as soon as possible.',
                $changes->{'Source'}, $changes->{'Version'}
            ),
        );

    }
    catch {
        $self->sendmail->send(
            from    => 'noreply@perlhub.ru',
            to      => $changes->{'Changed-By'} // $changes->{'Maintainer'},
            subject => gettext('Package %s (%s) was REJECTED', $changes->{'Source'}, $changes->{'Version'}),
            body    => shift->message(),
        );
    };

    unlink($changes_filename);
    unlink("$source_dir/$_") foreach map {[split(' ')]->[4]} grep {$_} split("\n", $changes->{'Files'});

    return $pkg_id;
}

TRUE;
