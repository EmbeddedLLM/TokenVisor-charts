# llm-d On-Prem Inference

llm-d is the second on-prem backend alongside SkyPilot. TokenVisor provisions each deployment as a vLLM Deployment plus an Endpoint Picker (EPP) and an InferencePool, all inside one namespace.

Unlike SkyPilot there is no API server to install: everything below is bootstrapped once into the `llm-d` namespace, and the backend then references it by name. Deployments themselves are created by TokenVisor at runtime.

The chart always installs this bootstrap — there is no on/off switch, because the backend has none either. Having the prerequisites in place is what "enabled" means to it, and a deployment create fails with `llm-d is not available` naming whichever one is missing.

## Prerequisites

The Gateway API Inference Extension CRDs are **not** installed by this chart — Helm cannot own CRDs another controller manages. `tokenvisor-prereqs platform` applies them alongside the Gateway API ones:

```bash
./bin/tokenvisor-prereqs platform --apply
```

Override the release with `GAIE_VERSION`, or apply it yourself:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.5.0/v1-manifests.yaml
```

Without them every deployment fails when its InferencePool is created. `tokenvisor-prereqs check` reports the CRD and the `llm-d` namespace as required items.

## Model storage

llm-d needs a `ReadWriteMany` PVC named `nfs-model-storage-pvc` in its namespace. Point it at the **same** backing storage as the `tokenvisor` and `skypilot` namespaces — the three share one HuggingFace cache, so a model pulled by one is not re-downloaded by the others.

`tokenvisor-prereqs storage model-pvcs` renders all three PV/PVC pairs against one SeaweedFS path:

```bash
./bin/tokenvisor-prereqs storage model-pvcs --path /shared_hf_repo --apply
```

For NFS, `k8s/manifest/nfs-model-storage-pv.yaml` and `-pvc.yaml` carry the same three-namespace layout.

Let the chart create the PVC instead when you are not using either path:

```yaml
llmd:
  modelPvc:
    create: true
    storageClassName: nfs-csi
    volumeName: nfs-pv-static-llm-d
    size: 1Ti
```

`create: false` (the default) assumes one of the paths above already applied it.

## Values

| Key                    | Default                 | Notes                                               |
| ---------------------- | ----------------------- | --------------------------------------------------- |
| `llmd.namespace`       | `llm-d`                 | Must match `EMU_LLMD_NAMESPACE`                     |
| `llmd.createNamespace` | `true`                  | Set `false` when the namespace is managed elsewhere |
| `llmd.serviceAccount`  | `llm-d-epp`             | **Fixed** — the backend expects this exact name     |
| `llmd.eppConfigMap`    | `llm-d-epp-config`      | Must match `EMU_LLMD_EPP_CONFIG_MAP`                |
| `llmd.envoyConfigMap`  | `llm-d-envoy-config`    | Must match `EMU_LLMD_ENVOY_CONFIG_MAP`              |
| `llmd.modelPvc.name`   | `nfs-model-storage-pvc` | **Fixed** — the backend mounts this exact name      |
| `llmd.modelPvc.*`      | see `values.yaml`       | Shared HuggingFace cache, `ReadWriteMany`           |

The namespace and the two ConfigMaps are settable, so the `emu.env.EMU_LLMD_*` entries and the `llmd:` section have to agree — both default to the same values; change them together.

The two marked **Fixed** have no `EMU_LLMD_*` counterpart: the backend hardcodes them, as it does `emu.modelStorage.existingClaim` and `storage.modelPvc.name` elsewhere in this chart. Changing them makes the chart build resources the backend will not look for, and every deployment then fails with `llm-d is not available` naming a resource you can see exists. They are exposed for templating, not for tuning.

## Component images

```yaml
emu:
  env:
    EMU_LLMD_EPP_IMAGE: "ghcr.io/llm-d/llm-d-router-endpoint-picker:v0.9.0"
    EMU_LLMD_ENVOY_IMAGE: "docker.io/envoyproxy/envoy:distroless-v1.33.2"
```

These are settable so an llm-d release can be taken, or a private registry mirror used, without waiting for a TokenVisor release. Air-gapped installs will need to repoint both.

**The EPP image is the one to change with care.** It owns the EndpointPickerConfig schema, so its version and the `apiVersion` inside `llm-d-epp-config` move together — bumping the image alone leaves every EPP pod crash-looping on a schema it does not recognise.

## Retuning the routing config

The EPP and Envoy configs are byte-identical for every model, which is why they are namespace-scoped rather than written per deployment. Scorer weights and Envoy settings can be changed in place:

```bash
kubectl edit configmap llm-d-epp-config -n llm-d
kubectl rollout restart deployment -n llm-d -l tokenvisor.ai/component=epp
```

No TokenVisor release is involved. Note that a `helm upgrade` re-applies the chart's copy, so persist any change you want to keep in `files/llmd/epp-config.yaml` or via a values override.

## Verify

```bash
# bootstrap resources
kubectl get sa,role,rolebinding,configmap,pvc -n llm-d

# a provisioned deployment (vLLM pods + EPP)
kubectl get deploy,svc,inferencepool -n llm-d
kubectl get pods -n llm-d -L tokenvisor.ai/model

# everything belonging to one deployment -- the id label is what TokenVisor
# reaps on, so this is exactly what housekeeping would tear down
kubectl get deploy,svc,inferencepool -n llm-d -l tokenvisor.ai/deployment-id=<id>
```

TokenVisor checks all of the above before provisioning and reports `llm-d is not available` naming the missing resource, so a failed deployment create points straight at the gap.

## Troubleshooting

| Symptom                                                                  | Cause                                           |
| ------------------------------------------------------------------------ | ----------------------------------------------- |
| `... the Gateway API Inference Extension (InferencePool CRD) is missing` | GAIE CRDs not installed                         |
| `... the shared model cache "nfs-model-storage-pvc" is missing`          | model PVC missing from the `llm-d` namespace    |
| `... the endpoint-picker service account "llm-d-epp" is missing`         | bootstrap RBAC not applied                      |
| EPP pods `CrashLoopBackOff` on 403s                                      | ServiceAccount or Roles missing                 |
| EPP pods stuck `CreateContainerConfigError`                              | a ConfigMap is missing or misnamed              |
| EPP rejects every request after an image bump                            | config schema no longer matches the EPP version |

A create that fails with a generic 500 rather than `llm-d is not available` means the cluster itself could not be reached — TokenVisor keeps the two apart, since "llm-d is not installed" and "the cluster is down" call for different fixes.

Logs for one deployment, across every replica:

```bash
kubectl logs -n llm-d -l tokenvisor.ai/deployment-id=<id>,tokenvisor.ai/component=vllm -f
kubectl logs -n llm-d -l tokenvisor.ai/deployment-id=<id>,tokenvisor.ai/component=epp -f
```
