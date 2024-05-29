# Secret Management

This cluster is set up to use sealed-secrets. 

This allows for SealedSecrets to appears in GitHub and be provisioned via Flux. 

Creating a SealedSecret will automatically create a secret for use in the cluster.

Sealed secrets need to be created via command line tool called `kubeseal`

Sealed secrets are also tied to the cluster, so if a cluster is created, I won't be able to decrpyt them in the future.


# Namespace-wide secrets

## 1. Create a secret 

Note: scope here is `namespace-wide`

```sh
# Change secret value
# Change namespace name
echo -n superdupersecret | kubeseal --raw --namespace default --scope namespace-wide
```

Copy the output.

## 2. Build a `SealedSecret` for use within a namespace

This will be bound to the namespace

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret # change secret name
  namespace: default # change namespace name
  annotations:
    sealedsecrets.bitnami.com/namespace-wide: "true"
spec:
  encryptedData:
    mysecretKey: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq..... # Add encrypted value here
```

# Cluster-wide secrets

## 1. Build a `SealedSecret for cluster-wide use

```sh
echo -n supersecret | kubeseal --raw --scope cluster-wide
```

## 2. Deploy 

```yaml

apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret # change secret name
  annotations:
    sealedsecrets.bitnami.com/cluster-wide: "true"
spec:
  encryptedData:
    mysecretKey: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq..... # Add encrypted value here
```