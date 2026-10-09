set -eu
rm -rf /s/stylelint && mkdir -p /s/stylelint/proj && cd /s/stylelint/proj
printf "{\"rules\": {\"color-hex-length\": \"short\", \"length-zero-no-unit\": true}}\n" > .stylelintrc.json
printf "a { color: #ffffff; margin: 0px; }\n" > a.css
