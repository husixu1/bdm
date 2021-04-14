# setup the environment
FROM archlinux as base_test_env
COPY --chown=1000:1000 ./tests/docker_setup.sh /
RUN bash ./docker_setup.sh

# Build the latest version of kcov,
# to avoid issues like https://github.com/SimonKagstrom/kcov/issues/325
FROM base_test_env as kcov
COPY --chown=1000:1000 ./tests/docker_kcov.sh /
RUN bash ./docker_kcov.sh

# copy the whole project
FROM base_test_env as complete_test_env
COPY --from=kcov /usr/local/bin/kcov /usr/local/bin
COPY --chown=1000:1000 . dotfiles
WORKDIR /dotfiles
ENTRYPOINT bash /dotfiles/tests/docker_test.sh
