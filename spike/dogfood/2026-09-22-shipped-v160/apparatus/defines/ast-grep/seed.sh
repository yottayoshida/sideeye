set -eu
rm -rf /s/sg && mkdir -p /s/sg/proj && cd /s/sg/proj
printf "id: no-var\nlanguage: javascript\nrule:\n  pattern: var \$A = \$B\nfix: let \$A = \$B\n" > rule.yml
printf "var x = 1;\nvar y = 2;\n" > a.js
