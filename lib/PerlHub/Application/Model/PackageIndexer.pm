package PerlHub::Application::Model::PackageIndexer;

use qbit;

use base qw(QBit::Application::Model);

__PACKAGE__->model_accessors(
    db            => 'PerlHub::Application::Model::DB',
    gpg           => 'PerlHub::Application::Model::GPG',
    package_build => 'PerlHub::Application::Model::PackageBuild',
);

use File::Path qw(make_path);
use File::Copy;
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Compress::Bzip2 qw(bzip2 $Bzip2Error);
use Fcntl qw(:flock);
use Dpkg::Control;

sub initialize_dirs {
    my ($self) = @_;

    make_path($self->get_option('packages_dir')) unless -d $self->get_option('packages_dir');

    foreach my $series (map {$_->{'name'}} @{$self->db->package_series->get_all(fields => [qw(name)])}) {
        my $series_dir = $self->get_option('packages_dir') . "/$series";
        mkdir($series_dir, 0700) unless -d $series_dir;

        foreach my $arch (map {$_->{'name'}} @{$self->db->package_arch->get_all(fields => [qw(name)])}) {
            my $pkg_dir = "$series_dir/$arch";
            next if -d $pkg_dir;

            mkdir($pkg_dir, 0700);
            writefile("$pkg_dir/Packages", '');
            __compress("$pkg_dir/Packages");
        }

        my $src_dir = "$series_dir/source";
        unless (-d $src_dir) {
            mkdir($src_dir, 0700);
            writefile("$src_dir/Sources", '');
            __compress("$src_dir/Sources");
        }
    }
}

sub publish_all {
    my ($self, %opts) = @_;

    my $var_path = $self->get_option('packages_dir') . '/var';
    make_path($var_path) unless -d $var_path;

    my %arch2id = map {$_->{'name'} => $_->{'id'}} @{$self->db->package_arch->get_all(fields => [qw(id name)])};

    foreach my $series (@{$self->db->package_series->get_all(fields => [qw(id name)])}) {
        open(my $fh, '>', "$var_path/.$series->{'name'}.lock")
          || throw gettext('Cannot create lock file: %s', Encode::decode_utf8($!));
        flock($fh, LOCK_EX) || throw gettext('Cannot lock: %s', Encode::decode_utf8($!));
        print $fh $$;

        my $incomming_path = $self->get_option('binaries_incomming_path') . "/$series->{'name'}";
        my $packages_path  = $self->get_option('packages_path') . "/$series->{'name'}";

        my $dh;
        unless (opendir($dh, $incomming_path)) {
            l gettext('Cannot open dir "%s": %s', $incomming_path, Encode::decode_utf8($!));
            next;
        }

        my @changes_files = grep {/\.changes$/} readdir($dh);
        closedir($dh);

        my @files2delete;
        my %changed_archs;
        my $changed_sources = FALSE;

        foreach my $changes_filename (@changes_files) {
            my $changes = Dpkg::Control->new(type => CTRL_FILE_CHANGES);
            $changes->load("$incomming_path/$changes_filename");

            $self->db->transaction(
                sub {
                    my $packages = $self->package_build->get_all(
                        fields => [qw(source_id series_id arch_id)],
                        filter => [
                            AND => [
                                [series_id => '=' => $series->{'id'}],
                                [
                                    arch_id => 'IN' =>
                                      [map {$arch2id{$_} // ()} split(/\s+/, $changes->{'Architecture'})]
                                ],
                                [multistate => '='     => 'completed'],
                                [source     => 'MATCH' => [name => '=' => $changes->{'Binary'}]],
                            ]
                        ],
                        for_update => TRUE,
                    );

                    $self->package_build->do_action($_, 'publish') foreach @$packages;

                    push(@files2delete, "$incomming_path/$changes_filename");
                    foreach (split("\n", $changes->{'Files'})) {
                        chomp();
                        next unless $_;
                        my $fn = [split(' ')]->[4];

                        push(@files2delete, "$incomming_path/$fn");

                        if ($fn =~ /_([a-z0-9]+)\.deb$/) {
                            $changed_archs{$1}++;
                            copy("$incomming_path/$fn", "$packages_path/$1/$fn") || throw gettext(
                                'Cannot copy file "%s" to "%s": %s', "$incomming_path/$fn",
                                "$packages_path/$1/$fn",             Encode::decode_utf8($!)
                            );
                        } elsif ($fn =~ /\.(?:tar\.|t)(?:gz|bz|bz2)$/ || $fn =~ /\.dsc$/) {
                            copy("$incomming_path/$fn", "$packages_path/source/$fn") || throw gettext(
                                'Cannot copy file "%s" to "%s": %s', "$incomming_path/$fn",
                                "$packages_path/source/$fn",         Encode::decode_utf8($!)
                            );
                            $changed_sources = TRUE;
                        }
                    }
                }
            );
        }

        if ($opts{'force_all'}) {
            %changed_archs = map {$_->{'name'} => TRUE} @{$self->db->package_arch->get_all(fields => [qw(name)])};
            $changed_sources = TRUE;
        }

        my @archs = keys(%changed_archs);
        push(@archs, 'source') if $changed_sources;

        $self->changed_archs($packages_path, $var_path, $series->{'name'}, @archs);

        unlink($_) foreach @files2delete;

        flock($fh, LOCK_UN) || throw gettext('Cannot unlock: %s', Encode::decode_utf8($!));
        close($fh);
    }
}

sub changed_archs {
    my ($self, $packages_path, $var_path, $series_name, @archs) = @_;

    my ($file, $lc_file);

    foreach my $arch (@archs) {
        my @files = (($arch eq 'source' ? 'Sources' : 'Packages'), 'Release');

        # Delete old files
        foreach my $f (@files) {
            foreach my $e ('', '.gz', '.bz2') {
                unlink("$packages_path/$arch/$f$e");
            }
        }

        $file    = shift(@files);
        $lc_file = lc($file);
`cd $packages_path/.. && /usr/bin/apt-ftparchive $lc_file --db $var_path/${series_name}_${arch}.db $series_name/$arch 2>/dev/null > $packages_path/$arch/$file`;
        __compress("$packages_path/$arch/$file");

        $file    = shift(@files);
        $lc_file = lc($file);
`cd $packages_path/.. && /usr/bin/apt-ftparchive $lc_file --db $var_path/${series_name}_${arch}.db -oAPT::FTPArchive::Release::Label=PerlHub -oAPT::FTPArchive::Release::Codename=$series_name/$arch -oAPT::FTPArchive::Release::Architectures=$arch $series_name/$arch 2>/dev/null > $packages_path/$arch/$file`;
        __compress("$packages_path/$arch/$file");

        $self->gpg->sign("$packages_path/$arch/$file");
    }
}

sub __compress {
    my ($filename) = @_;

    gzip($filename, "$filename.gz")
      || throw gettext('Cannot compress file "%s": %s', $filename, Encode::decode_utf8($GzipError));
    bzip2($filename, "$filename.bz2")
      || throw gettext('Cannot compress file "%s": %s', $filename, Encode::decode_utf8($Bzip2Error));
}

TRUE;
