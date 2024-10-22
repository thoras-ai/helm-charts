## Install helm unit test

```
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

## Run unit tests

```
helm unittest ./charts/thoras --chart-tests-path ./charts/thoras/tests
```
