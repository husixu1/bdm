# 0. Build a base environment for subsequent building
FROM archlinux as base
COPY --chown=1000:1000 ./tests/docker_base_env.sh /
RUN bash ./docker_base_env.sh

FROM base as build_base
RUN pacman -S --noconfirm base-devel cmake python

# 1. Build the latest version of kcov,
# to avoid issues like https://github.com/SimonKagstrom/kcov/issues/325
FROM build_base as kcov
COPY --chown=1000:1000 ./tests/docker_kcov.sh /
RUN bash ./docker_kcov.sh

# 2. build bdm
FROM build_base as build_bdm
COPY --chown=1000:1000 . /dotfiles
WORKDIR /dotfiles
RUN bash -c 'autoreconf -i && ./configure && make dist'

# 3. test the whole project
FROM base as test_bdm
# copy kcov and bdm builds
COPY --from=kcov /usr/local/bin/kcov /usr/local/bin
COPY --from=build_bdm --chown=1000:1000 /dotfiles/bdm-*.tar.gz /home/user
# build and test bdm
COPY --chown=1000:1000 ./tests /tests
ENTRYPOINT bash /tests/docker_test.sh
