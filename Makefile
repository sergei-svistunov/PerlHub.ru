all: gen_deb_crond

gen_deb_crond:
	@NO_PKG_INEXER_INIT=yes perl -Ilib -MPerlHub::Cron -e "PerlHub::Cron->new()->generate_crond(mail_to => 'cron@perlhub.ru', user => 'www-data', application_path => '/usr/share/perlhub/lib')" > debian/perlhub.cron.d

db_create_sql:
	@NO_PKG_INEXER_INIT=yes perl -Ilib -MPerlHub::Application -e 'my $$app = PerlHub::Application->new(); $$app->pre_run(); print $$app->db->create_sql()'

create_and_copy_configs:
	@if test \! -d nginx; then \
		mkdir nginx; \
	fi
	@perl beta/create_init_and_config.pl
	@cp beta/init.sh beta/nginx.conf nginx/
	@cp beta/Application.cfg beta/WebInterface.cfg lib/PerlHub/
	@chmod a+x nginx/init.sh

save_configs:
	@rm -rf ./.beta_saved
	@mkdir ./.beta_saved
	@cp beta/init.sh beta/nginx.conf beta/Application.cfg beta/WebInterface.cfg .beta_saved/
	@rm beta/init.sh beta/nginx.conf beta/Application.cfg beta/WebInterface.cfg
	
beta_create: create_and_copy_configs save_configs nginx/perlhub/sign_gpg
	@mkdir -p ./nginx/dput_upload
	@./nginx/init.sh restart
	
beta_update: nginx/perlhub/sign_gpg
	@if test \! -d .beta_saved; then \
         echo "Create beta with \"make beta_create\""; \
         exit 1; \
     fi
	@perl beta/create_init_and_config.pl
	@diff -c .beta_saved/init.sh          beta/init.sh          | patch --no-backup-if-mismatch ./nginx/init.sh
	@diff -c .beta_saved/nginx.conf       beta/nginx.conf       | patch --no-backup-if-mismatch ./nginx/nginx.conf
	@diff -c .beta_saved/Application.cfg  beta/Application.cfg  | patch --no-backup-if-mismatch ./lib/PerlHub/Application.cfg
	@diff -c .beta_saved/WebInterface.cfg beta/WebInterface.cfg | patch --no-backup-if-mismatch ./lib/PerlHub/WebInterface.cfg
	@$(MAKE) --no-print-directory save_configs
	@mkdir -p ./nginx/dput_upload
	@./nginx/init.sh restart

nginx/perlhub/sign_gpg:
	mkdir -p nginx/perlhub/sign_gpg
	printf "Key-Type: 1\nKey-Length: 2048\nName-Real: PerlHub\nName-Email: no_reply@perlhub.ru\nExpire-Date: 0\n" | gpg --homedir nginx/perlhub/sign_gpg --gen-key --batch --yes --no-secmem-warning --no-permission-warning
