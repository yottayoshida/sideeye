set -eu
rm -rf /s/bibtex && mkdir -p /s/bibtex
printf '@article{knuth1984,\n  title={Literate Programming},\n  author={Knuth, Donald E.},\n  journal={The Computer Journal},\n  year={1984}\n}\n\n@book{abelson1996,\n title = {Structure and Interpretation of Computer Programs},\n author = {Abelson, Harold and Sussman, Gerald Jay},\n year = 1996, publisher={MIT Press}\n}\n' > /s/bibtex/refs.bib
