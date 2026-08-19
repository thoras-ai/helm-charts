# Development

## Tests and Checks

### pre-commit

Install [pre-commit](https://github.com/pre-commit/pre-commit) with your preferred package manager, for example:

```bash
brew install pre-commit
# or
pipx install pre-commit
# or
pip install pre-commit
```

Run all hooks against every file:

```bash
pre-commit run --all-files
```

### helm unittest

Install unittest plugin

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

Run tests

```bash
helm unittest ./charts/thoras --chart-tests-path ./charts/thoras/tests
```
