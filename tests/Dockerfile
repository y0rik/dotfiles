# Local test image: bats + yq, matching what CI's ubuntu-latest runner provides.
#   docker build -t dotfiles-test tests/ && docker run --rm -v "$PWD:/code:ro" -w /code dotfiles-test tests/
FROM mikefarah/yq:4.44.3 AS yq
FROM bats/bats:1.11.0
COPY --from=yq /usr/bin/yq /usr/bin/yq
