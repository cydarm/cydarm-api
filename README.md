# cydarm-api



# Build image

```bash
docker compose build --ssh default
```

# Build docs

```bash
docker compose run --rm -it -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock -v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock --env RELEASE_VERSION=v26.6.0 api-docs
```

Docs will be output to the `./docs` directory.
The latest version of the openapi yaml spec (per version sort) will also be copied to `./docs/openapi.yaml`

The updated docs in `./docs` then need to be committed.
