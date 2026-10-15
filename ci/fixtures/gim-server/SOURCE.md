# gim-server fixture

Runtime source of [gim-server](https://github.com/gimhq/gim-server) at commit
`12e316ea134828ec332f6e0a3d08fb9aa9cb617d`, vendored unmodified with:

```sh
git -C <gim-server checkout> archive 12e316e src package.json bun.lock tsconfig.json | tar -x -C ci/fixtures/gim-server
```

Purpose: the M2.0 device E2E job starts this server on the CI runner (`scripts/start-gim-server.sh`) without reading
the private gim-server repository. gim-server is frozen at this commit; M2 moves to gim-hub, so this fixture is not
refreshed. Apart from this file, every file is byte-identical to the archive output.
