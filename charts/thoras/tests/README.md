## Install helm unit test

```
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

## Write your first test
For an example, see `tests/dashboard_deployment_test.yaml`

## Run unit tests

From the repo's root directory, run the following command
```
helm unittest ./charts/thoras --chart-tests-path ./charts/thoras/tests
```
