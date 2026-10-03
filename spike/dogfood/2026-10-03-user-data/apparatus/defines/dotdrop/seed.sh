set -eu
rm -rf /s/dotdrop /s/dotdrop-in && mkdir -p /s/dotdrop/home /s/dotdrop-in/dotfiles
printf 'config:\n  backup: true\n  create: true\n  dotpath: dotfiles\ndotfiles:\n  f_bashrc:\n    src: bashrc\n    dst: /s/dotdrop/home/.bashrc\n  f_gitconfig:\n    src: gitconfig\n    dst: /s/dotdrop/home/.gitconfig\nprofiles:\n  host:\n    dotfiles:\n    - f_bashrc\n    - f_gitconfig\n' > /s/dotdrop-in/config.yaml
printf 'export EDITOR=vim\nalias ll="ls -l"\n' > /s/dotdrop-in/dotfiles/bashrc
printf '[user]\n\tname = me\n' > /s/dotdrop-in/dotfiles/gitconfig
printf '# my local bashrc, hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotdrop/home/.bashrc
printf '[user]\n\tname = old\n' > /s/dotdrop/home/.gitconfig
