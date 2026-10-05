set -eu
rm -rf /s/i18n && mkdir -p /s/i18n/config/locales /s/i18n/app/views/home && cd /s/i18n
printf 'en:\n  home:\n    index:\n      title: Welcome\n' > config/locales/en.yml
printf 'ja:\n  home:\n    index:\n      title: ようこそ\n' > config/locales/ja.yml
printf "<h1><%%= t('.title') %%></h1>\n<p><%%= t('.intro') %%></p>\n<p><%%= t('home.index.footer') %%></p>\n" > app/views/home/index.html.erb
