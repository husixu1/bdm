# necessary depends for building/running/testing the package
# required for building: make
# required for running: sudo
# required for testing: which diff
pacman -Syu --noconfirm
pacman -S --noconfirm make sudo which diffutils

# install bash_unit
mkdir -p /usr/local/bin
pushd /usr/local/bin || exit 1
bash <(curl -s https://raw.githubusercontent.com/pgrange/bash_unit/master/install.sh)
popd || exit 1

# create user for testing, and set its password
groupadd user -g 1000
useradd -u 1000 -g 1000 -m user

# enable sudo access for user
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
