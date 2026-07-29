# TRELLIS.2 RTX 4090 512³ rebuild and compliance playbook

This document is the durable rebuild guide for the Impassable Games
TRELLIS.2 image-to-3D workstation. It records the original installation plan,
the changes that made the pipeline usable without `nvdiffrast`,
`nvdiffrec`, or BRIA, the exact state that was tested, and the controls needed
to generate commercially reviewed assets for a Steam game.

The reference implementation was validated on **2026-07-29**. Treat every
version and revision below as a reproducibility pin, not as a suggestion to
silently upgrade to whatever is newest.

> [!IMPORTANT]
> This is a technical and evidentiary workflow, not a legal opinion. It can
> prove what code, packages, checkpoints, inputs, and settings were observed
> for a run. It cannot guarantee that a generated object does not resemble a
> third-party work or resolve unsettled questions about model training data.

## Current conclusion

The 512³ pipeline works on the reference RTX 4090 machine. It has produced
recognizable, textured GLB files from simple input images, and the resulting
files passed structural validation.

The working design is:

- Ubuntu 22.04 under WSL 2;
- NVIDIA's Windows WSL driver, with CUDA Toolkit 12.4 installed inside WSL;
- Python 3.10 and PyTorch 2.6.0 with CUDA 12.4;
- the 512³ TRELLIS.2 model path only;
- PyTorch3D in place of `nvdiffrast` and `nvdiffrec`;
- BiRefNet as the default background remover;
- `rembg`/U²-Net as an installed and tested CPU fallback;
- exact Hugging Face checkpoint revisions recorded in compliance evidence;
- a separate private, text-only compliance and provenance repository.

There is one important production blocker in the current source state:
the custom TRELLIS.2 implementation is based on upstream commit
`75fbf0183001ed9876c8dbb35de6b68552ee08bd`, but its modifications are still
an uncommitted working tree in the local Microsoft checkout. Before recording
production assets, create a private fork, commit the complete implementation,
push it, and use that immutable commit. The provenance tool intentionally
rejects a dirty source tree by default.

## What “commercially reviewed” means here

The modified dependency path avoids the known NVIDIA Source Code License
components and the original BRIA checkpoint. That is useful, but it is not the
same as a blanket promise that every output is legally safe.

For each production asset, review four separate layers:

1. **Distributed game files** — audit every library and asset actually shipped.
2. **Generation tooling** — record the inference environment even if it never
   ships with the game.
3. **Model checkpoints** — pin the exact revision and archive its license
   evidence or a revision-specific attestation.
4. **Inputs and outputs** — prove the input image rights and manually review the
   output for recognizable third-party designs, trademarks, or close copying.

Only generated game assets are intended to ship. The WSL environment, Python
packages, model weights, and inference server are build tools, not game
runtime dependencies. This distribution boundary matters when assessing
copyleft packages, but it should still be reviewed with qualified counsel
before release.

## Validated reference state

| Component | Validated state |
| --- | --- |
| Host | 64-bit Windows, build `26200.8875`, 25H2 |
| WSL | WSL `2.7.11.0`; kernel `6.18.33.2-2`; WSL 2 |
| Distribution | Ubuntu `22.04.5 LTS` |
| GPU | NVIDIA GeForce RTX 4090, 24,564 MiB, compute capability 8.9 |
| Windows NVIDIA driver | `610.88` |
| Linux NVIDIA driver package | None; WSL uses the Windows driver bridge |
| CUDA Toolkit in WSL | `cuda-toolkit-12-4` `12.4.1-1` |
| `nvcc` | CUDA 12.4, build `cuda_12.4.r12.4/compiler.34097967_0` |
| Conda | `26.5.3` |
| Python | `3.10.20` |
| PyTorch | `2.6.0+cu124` |
| Torchvision | `0.21.0+cu124` |
| PyTorch3D | `0.7.9` |
| FlashAttention | `2.7.3` |
| Transformers | `5.14.1` |
| Hugging Face Hub | `1.25.1` |
| OpenCV wheel | `opencv-python-headless 5.0.0.93` |
| Background removal | BiRefNet default; `rembg 2.0.67`/U²-Net fallback |
| TRELLIS.2 upstream base | `75fbf0183001ed9876c8dbb35de6b68552ee08bd` |
| Eigen submodule | `21e458d56a673b626d82227f3f29aaea5c2f3c6a` |
| PyTorch3D source | `33824be3cbc87a7dd1db0f6a9a9de9ac81b2d0ba` |
| CuMesh source | `12289e1062f0603f2f0d0771b02e1395d247f26f` |
| FlexGEMM source | `6dd94a859c26ee8246888502eada3dd8ad85532e` |
| Supported generation profile | 512³ only |
| GLB export profile | About 500,000 faces; 2,048 px PBR textures |

Some Windows APIs still label recent Windows builds as “Windows 10” for
compatibility. Record the build and display version rather than relying on
that legacy product-name string.

## Architecture

```text
Windows NVIDIA WSL driver
        │
        ▼
Ubuntu 22.04 / WSL 2
        │
        ├── CUDA Toolkit 12.4 (compiler and user-space toolkit only)
        │
        ├── conda environment: trellis2
        │   ├── PyTorch 2.6.0+cu124
        │   ├── PyTorch3D renderer/rasterizer
        │   ├── TRELLIS.2 512³ pipeline
        │   ├── BiRefNet default background removal
        │   └── rembg/U²-Net CPU fallback
        │
        ├── external model cache
        │   └── exact Hugging Face revisions
        │
        ├── external binary asset storage
        │   └── GLB, images, previews, and checkpoints
        │
        └── private compliance Git repository
            ├── append-only dated audits
            ├── package and model evidence
            ├── JSON provenance sidecars
            └── SHA-256-chained manifest
```

## How the final design differs from the original roadmap

| Original direction | Final direction | Reason |
| --- | --- | --- |
| Reuse or repair WSL | Rebuild Ubuntu 22.04 from scratch when needed | Removes unknown state and makes the process easier to audit |
| Install official TRELLIS dependencies including `nvdiffrast`/`nvdiffrec` | Do not install them; use PyTorch3D | Avoids the NVIDIA Source Code License path |
| Use the upstream BRIA background remover | BiRefNet by default | BRIA's checkpoint terms were unsuitable for the intended commercial workflow |
| One background remover | Keep `rembg`/U²-Net as a fallback | Preserves an operational path if BiRefNet access or terms change |
| Keep upstream 512 and 1024 paths | Load and expose 512 only | 512 is sufficient and lowers memory, time, and complexity |
| Assume EXR environment maps work | Try EXR, then use a checked-in PNG fallback | The validated OpenCV wheel had no functional EXR decoder |
| Use package names as model identity | Record repository plus exact revision | A repository name alone does not prove which weights were used |
| Rely on a one-time license review | Re-run deterministic compliance tools | Dated, immutable evidence is more useful than “it was removed” |

## Phase 0 — establish the evidence rules first

Do this before installing the model stack.

### Keep code, evidence, and binaries separate

- The TRELLIS.2 implementation belongs in a private source fork.
- Compliance tools and text/JSON evidence belong in the private
  `impassable_games_assets` repository.
- Generated GLB files, images, videos, Blender files, and model weights belong
  in external binary storage.
- Each binary is connected to Git records by SHA-256 and a stable storage
  location.

The compliance repository should ignore at least:

```gitignore
*.glb
*.fbx
*.blend
*.blend1
*.obj
*.usdz
*.png
*.jpg
*.exr
*.hdr
*.safetensors
*.ckpt
*.pth
```

Also ignore TRELLIS intermediate-output and local model-weight directories.
Do not commit temporary signed URLs, access tokens, national or tax IDs, bank
details, or any other raw secret.

### Pin every mutable input

A reproducible run needs all of the following:

- TRELLIS.2 implementation commit;
- Git commits for native extensions;
- complete conda and pip inventories;
- CycloneDX SBOM hash;
- exact checkpoint repository IDs and revisions;
- checkpoint license evidence;
- input image hash, source, and rights status;
- output hash and external storage location;
- UTC generation timestamp;
- generation settings.

“Latest,” `main`, a floating Hugging Face cache reference, and a dirty Git tree
are not production pins.

## Phase 1 — Windows preflight

Run these in an elevated PowerShell window:

```powershell
Get-ComputerInfo |
  Select-Object WindowsProductName, WindowsVersion, OsBuildNumber,
    OsArchitecture, CsTotalPhysicalMemory

wsl --version
wsl --status
wsl --list --verbose
nvidia-smi
```

Confirm:

- hardware virtualization is enabled;
- Ubuntu will run as WSL version 2;
- the RTX 4090 appears in `nvidia-smi`;
- there is enough free SSD space for environments, build files, cache, and
  outputs;
- Windows Update and the NVIDIA driver are current enough for WSL CUDA.

Do not install a Linux display driver inside WSL. The Windows NVIDIA driver
provides the GPU bridge. Only the CUDA toolkit is installed in Ubuntu.

## Phase 2 — optionally recreate Ubuntu 22.04

This is intentionally destructive. Export anything that must survive:

```powershell
wsl --shutdown
New-Item -ItemType Directory -Force C:\wsl-backups
wsl --export Ubuntu-22.04 C:\wsl-backups\Ubuntu-22.04-before-trellis.tar
Get-Item C:\wsl-backups\Ubuntu-22.04-before-trellis.tar
```

After verifying the export exists, unregister and reinstall:

```powershell
wsl --shutdown
wsl --unregister Ubuntu-22.04
wsl --install --distribution Ubuntu-22.04
wsl --set-version Ubuntu-22.04 2
wsl --set-default Ubuntu-22.04
```

`wsl --unregister` deletes that distribution's filesystem. It does not delete
ordinary Windows files outside the distribution, but paths and backups must
still be checked carefully before running it.

At first launch, Ubuntu asks for a Linux username and password. This password:

- has no default value;
- is independent of the Windows account password;
- is independent of the Hugging Face account and token;
- is used by `sudo`.

If it is forgotten, reset it from an elevated PowerShell window:

```powershell
wsl --distribution Ubuntu-22.04 --user root -- passwd <linux-user>
```

## Phase 3 — install Ubuntu build prerequisites

Inside Ubuntu:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  ffmpeg \
  git \
  git-lfs \
  libgl1 \
  libglib2.0-0 \
  ninja-build \
  pkg-config \
  unzip \
  wget

git lfs install
```

Keep active source trees and environments in the Linux filesystem, such as
`~/ai`, rather than under `/mnt/c`. Native compilation and many-file workloads
are normally faster there. Windows paths are suitable for the small text-only
compliance repository and for intentional file exchange.

Verify the driver bridge from inside WSL:

```bash
nvidia-smi
ls -l /usr/lib/wsl/lib/libcuda.so*
dpkg -l | grep -E '^ii[[:space:]]+nvidia-driver-' || true
```

The final command should return no installed Linux driver package.

## Phase 4 — install CUDA Toolkit 12.4 inside WSL

Use NVIDIA's WSL Ubuntu repository and install the toolkit package, not a
driver-bearing metapackage:

```bash
cd /tmp
wget \
  https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit-12-4
```

Avoid `cuda`, `cuda-12-4`, and `cuda-drivers` metapackages in WSL if they try
to add a Linux display driver.

Create a small environment file:

```bash
mkdir -p ~/.config/trellis2
editor ~/.config/trellis2/env.sh
```

Use:

```bash
#!/usr/bin/env bash
export CUDA_HOME=/usr/local/cuda-12.4
export CUDACXX="${CUDA_HOME}/bin/nvcc"
export PATH="${CUDA_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export LIBRARY_PATH="/usr/lib/wsl/lib:${CUDA_HOME}/lib64${LIBRARY_PATH:+:${LIBRARY_PATH}}"
export MAX_JOBS=4
export TORCH_CUDA_ARCH_LIST=8.9
export OPENCV_IO_ENABLE_OPENEXR=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export TRELLIS2_REMBG_MODEL=ZhengPeng7/BiRefNet
export TRELLIS2_RENDER_BACKEND=pytorch3d
```

Load and verify it:

```bash
source ~/.config/trellis2/env.sh
command -v nvcc
echo "$PATH"
nvcc --version
nvidia-smi
```

CUDA not appearing on the default shell `PATH` before this file is sourced is
expected. The environment file makes the build context explicit.

## Phase 5 — create the Python environment

Install Miniconda from its official distribution. Save the installer SHA-256
with the setup evidence because the `latest` URL is not immutable:

```bash
curl -fsSLo /tmp/miniconda.sh \
  https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
sha256sum /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"

eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda create -y --name trellis2 python=3.10
conda activate trellis2
python --version
```

Install the validated PyTorch CUDA wheels:

```bash
python -m pip install --upgrade pip setuptools wheel
python -m pip install \
  torch==2.6.0 \
  torchvision==0.21.0 \
  --index-url https://download.pytorch.org/whl/cu124
```

Verify a real CUDA operation:

```bash
python - <<'PY'
import torch

print("torch:", torch.__version__)
print("built for CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
print("GPU:", torch.cuda.get_device_name(0))
x = torch.randn((2048, 2048), device="cuda")
print("matmul mean:", (x @ x).mean().item())
PY
```

The expected high-level result is PyTorch `2.6.0+cu124`, CUDA `12.4`,
`True`, and the RTX 4090.

The compliance run's `conda-environment.yml`, `conda-list.json`,
`pip-freeze.txt`, and `pip-list.json` are the exact observed inventory and
should be used as the version ledger. They are not, by themselves, a portable
one-command lock: PyTorch needs the CUDA 12.4 wheel index, and CuMesh,
FlexGEMM, PyTorch3D, and `o-voxel` need their recorded source origins and Git
commits. Recreate those sources explicitly, then compare the new inventories
and SBOM with the known-good run.

## Phase 6 — obtain an immutable TRELLIS.2 source revision

For investigation, the upstream base can be recreated as follows:

```bash
mkdir -p ~/ai
cd ~/ai
git clone --recurse-submodules https://github.com/microsoft/TRELLIS.2.git
cd TRELLIS.2
git checkout 75fbf0183001ed9876c8dbb35de6b68552ee08bd
git submodule update --init --recursive
```

For production, do not stop there. The intended source of truth is a private
fork containing the renderer, rasterizer, background-removal, 512-only, DINO,
and EXR compatibility work described below:

```bash
git clone --recurse-submodules \
  git@github.com:<private-owner>/<private-trellis2-fork>.git \
  ~/ai/TRELLIS.2
cd ~/ai/TRELLIS.2
git checkout <reviewed-implementation-commit>
git submodule update --init --recursive
git status --porcelain
```

The last command must produce no output. Never push the custom work directly
to Microsoft's upstream repository. Record both the upstream base and the
private implementation commit.

## Phase 7 — install dependencies without the restricted renderer path

Source the CUDA settings and activate the environment for every build shell:

```bash
source ~/.config/trellis2/env.sh
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda activate trellis2
cd ~/ai/TRELLIS.2
```

Use the upstream installer only for the basic Python dependencies and
FlashAttention:

```bash
bash setup.sh \
  --basic \
  --flash-attn
```

Do **not** pass any `nvdiffrast` or `nvdiffrec` option. Do not later install
them “just to make an import work”; that defeats the design and the absence
proof.

Do not use the setup script's CuMesh or FlexGEMM groups for a strict rebuild:
those groups clone moving default branches. Pin native extension checkouts:

| Source | Required commit | Recorded license |
| --- | --- | --- |
| `facebookresearch/pytorch3d` | `33824be3cbc87a7dd1db0f6a9a9de9ac81b2d0ba` | BSD-3-Clause |
| CuMesh | `12289e1062f0603f2f0d0771b02e1395d247f26f` | MIT |
| FlexGEMM | `6dd94a859c26ee8246888502eada3dd8ad85532e` | MIT |
| local `o-voxel` | same private TRELLIS implementation commit | MIT under repository scope |

Build PyTorch3D against the active PyTorch/CUDA environment:

```bash
mkdir -p ~/ai/trellis2-extension-sources
cd ~/ai/trellis2-extension-sources
git clone https://github.com/facebookresearch/pytorch3d.git
cd pytorch3d
git checkout 33824be3cbc87a7dd1db0f6a9a9de9ac81b2d0ba
git status --porcelain
python -m pip install --no-build-isolation .
```

Install the other native extensions from their exact commits:

```bash
cd ~/ai/trellis2-extension-sources
git clone --recursive https://github.com/JeffreyXiang/CuMesh.git
cd CuMesh
git checkout 12289e1062f0603f2f0d0771b02e1395d247f26f
git submodule update --init --recursive
python -m pip install --no-build-isolation .

cd ~/ai/trellis2-extension-sources
git clone --recursive https://github.com/JeffreyXiang/FlexGEMM.git
cd FlexGEMM
git checkout 6dd94a859c26ee8246888502eada3dd8ad85532e
git submodule update --init --recursive
python -m pip install --no-build-isolation .
```

Install `o-voxel` only after the private source modifications in Phase 8 have
been applied.

## Phase 8 — implement the permissive rendering and export path

The replacement is an implementation project, not a package-name substitution.
The TRELLIS code expects specific renderer behavior, UV-space rasterization,
environment-map handling, and PBR export data.

The validated private implementation must preserve these changes:

| File | Required behavior |
| --- | --- |
| `trellis2/renderers/__init__.py` | Export the permissive `EnvMap`, `MeshRenderer`, and `PbrMeshRenderer` classes |
| `trellis2/renderers/permissive_mesh_renderer.py` | Implement mesh and PBR rendering with PyTorch/PyTorch3D; no `nvdiffrast` import |
| `o-voxel/o_voxel/rasterization.py` | Rasterize UV meshes with PyTorch3D's `rasterize_meshes` and interpolate 3D positions |
| `o-voxel/o_voxel/postprocess.py` | Use the PyTorch3D UV helper during GLB texture baking |
| `trellis2/pipelines/trellis2_texturing.py` | Use the same UV helper and load the 512 texture-flow path only |
| `app.py` and `app_texturing.py` | Offer only the 512 profile and use the environment-map fallback |
| `example.py` and `example_512.py` | Run the same 512-only export path |
| `verify-install.py` | Prove required imports, forbidden absence, CUDA execution, and active renderer module paths |
| `validate-glb.py` | Validate the binary GLB structure, mesh, material, and textures |

The replacement renderer currently contains:

- PyTorch3D mesh rasterization;
- barycentric interpolation;
- UV and texture sampling;
- normal, material, and environment-map handling;
- a PBR approximation compatible with the downstream TRELLIS preview/export
  contracts.

It is not expected to be pixel-identical to NVIDIA's renderer. The acceptance
criterion is functional 512 generation, usable preview rendering, valid PBR
texture export, and no active or installed forbidden renderer.

Install the patched `o-voxel` package from the private checkout:

```bash
cd ~/ai/TRELLIS.2/o-voxel
python -m pip install --no-build-isolation .
```

If it was ever installed before the rasterization changes were applied,
reinstall it now. Confirm that the installed `postprocess.py` and
`rasterization.py` hashes match the private source files.

Search both source and the installed environment:

```bash
cd ~/ai/TRELLIS.2
rg -n -i 'nvdiffrast|nvdiffrec|nvidia source code license' .

python - <<'PY'
import importlib.util

for name in ("nvdiffrast", "nvdiffrec", "nvdiffrec_render"):
    print(name, importlib.util.find_spec(name))
PY
```

A source mention in documentation or an absence-check list is not an import.
Review every match by context. The module lookups must return `None`.

## Phase 9 — background removal

### BiRefNet default

The default checkpoint is pinned to:

```text
ZhengPeng7/BiRefNet
revision e2bf8e4460fc8fa32bba5ea4d94b3233d367b0e4
```

The repository owner resolved the earlier ambiguity in
[BiRefNet issue #316](https://github.com/ZhengPeng7/BiRefNet/issues/316#issuecomment-5120372022)
with the statement:

> All the codes and weights are under the MIT license.

The compliance repository archives the verbatim comment, author, permalink,
date, and the README served at the exact revision. The attestation applies
only to that revision. A new revision must be reviewed again. The maintainer
also stated an intention to add a LICENSE file to the Hugging Face model
repository; archive that file as additional evidence if it appears.

The BiRefNet wrapper must:

- allow-list `ZhengPeng7/BiRefNet`;
- expose the active repository ID;
- handle device and dtype explicitly;
- return RGBA output expected by the pipeline;
- avoid silently changing to an arbitrary repository from configuration.

### Keep the U²-Net fallback

The selector reads `trellis2/pipelines/rembg/backend_config.json`, with
BiRefNet as the default and `rembg_u2net` selectable through:

```bash
export TRELLIS2_REMBG_BACKEND=rembg_u2net
```

The validated fallback state is:

| Item | Value |
| --- | --- |
| Package | `rembg==2.0.67` |
| Runtime | `onnxruntime==1.23.2`, CPU |
| Model | `u2net.onnx` |
| SHA-256 | `8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491` |
| Source URL | `https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx` |

Do not merely retain the package. The full compliance run checks the
configured default, fallback selector, model hash, and a real ONNX inference.

## Phase 10 — fix the pipeline to 512³

The reference machine does not need the 1024 or 1536 profiles.

In both image-to-3D and texturing pipelines:

- make `512` the default;
- load only the model components needed by the 512 path;
- reject or remove UI choices for larger profiles;
- ensure validation fails if a loaded model name contains `1024`;
- keep preview rendering at 512;
- use a 500,000-face simplification/export target;
- use 2,048 px export textures.

The 512³ pipeline resolution and the 2,048 px exported texture size describe
different stages. A 512 pipeline can still export 2,048 px material textures.

## Phase 11 — authenticate and pin model checkpoints

Use a Hugging Face token with read-only access. Log in interactively:

```bash
source ~/.config/trellis2/env.sh
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda activate trellis2
hf auth login
hf auth whoami
```

Paste the token only at the hidden interactive prompt. Never put it in a shell
command, script, Git file, issue, chat message, or captured log. The Hugging
Face token is not the WSL `sudo` password and is not the website password.

Download and verify exact revisions:

```bash
hf download microsoft/TRELLIS.2-4B \
  --revision af44b45f2e35a493886929c6d786e563ec68364d \
  --quiet

hf download microsoft/TRELLIS-image-large \
  --revision 25e0d31ffbebe4b5a97464dd851910efc3002d96 \
  --quiet

hf download facebook/dinov3-vitl16-pretrain-lvd1689m \
  --revision ea8dc2863c51be0a264bab82070e3e8836b02d51 \
  --quiet

hf download ZhengPeng7/BiRefNet \
  --revision e2bf8e4460fc8fa32bba5ea4d94b3233d367b0e4 \
  --quiet
```

| Model | Exact revision | Recorded basis |
| --- | --- | --- |
| `microsoft/TRELLIS.2-4B` | `af44b45f2e35a493886929c6d786e563ec68364d` | MIT under the upstream model scope |
| `microsoft/TRELLIS-image-large` | `25e0d31ffbebe4b5a97464dd851910efc3002d96` | MIT under the related TRELLIS repository scope |
| `facebook/dinov3-vitl16-pretrain-lvd1689m` | `ea8dc2863c51be0a264bab82070e3e8836b02d51` | DINOv3 License, verified custom terms |
| `ZhengPeng7/BiRefNet` | `e2bf8e4460fc8fa32bba5ea4d94b3233d367b0e4` | MIT, exact-revision maintainer attestation |

The validated DINOv3 `model.safetensors` was 1,212,559,808 bytes with SHA-256:

```text
dcb2e45127cccbf1601e5f42fef165eea275c8e5213197e8dcf3f48822718179
```

The project credits policy requires the shipped game to display:

```text
Built with DINOv3
```

### Remaining model-loading hardening

The current pipeline calls `from_pretrained` with repository IDs but without
passing a revision at every runtime call. A cache audit proves what was
present; it does not by itself force a future online call to use that revision.

Before production, make one of these approaches part of the committed private
implementation:

1. pass the exact `revision=` value to every `from_pretrained` call; or
2. resolve and use the exact local snapshot path, then run with
   `local_files_only=True`.

After all exact snapshots and license files are verified, production workers
can set `HF_HUB_OFFLINE=1` to prevent a floating network resolution. Test that
mode before depending on it.

## Phase 12 — Transformers/DINOv3 compatibility

With Transformers `5.14.1`, the DINO encoder layers may be nested under:

```python
self.model.model.layer
```

rather than:

```python
self.model.layer
```

`trellis2/modules/image_feature_extractor.py` must resolve both known layouts
and fail with a clear error if neither exists. Do not catch an arbitrary
`AttributeError` and continue with a partial feature extractor.

The targeted validation for the fixed path produced a finite CUDA tensor with
shape:

```text
[1, 1029, 1024]
```

## Phase 13 — environment-map compatibility

Setting `OPENCV_IO_ENABLE_OPENEXR=1` was insufficient on the validated
`opencv-python-headless 5.0.0.93` wheel: the EXR decoder was not available.

`EnvMap.from_file` therefore:

1. tries the EXR path;
2. verifies that loading succeeded;
3. uses an explicit PNG fallback such as
   `assets/app/hdri_forest.png`;
4. fails clearly if neither source is usable.

Example:

```python
envmap = EnvMap.from_file(
    "assets/hdri/forest.exr",
    fallback_path="assets/app/hdri_forest.png",
)
```

Do not treat the PNG fallback as a hidden exception. It is a supported part of
the validated configuration.

## Phase 14 — installation and pipeline gates

Run the lightweight installation gate first:

```bash
source ~/.config/trellis2/env.sh
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda activate trellis2
cd ~/ai/TRELLIS.2
python verify-install.py
```

It should prove:

- CUDA is available and performs a real matrix multiplication;
- `trellis2`, `o_voxel`, `pytorch3d`, `flash_attn`, `cumesh`, and
  `flex_gemm` import;
- `nvdiffrast` and `nvdiffrec_render` do not import;
- the active UV rasterizer is `o_voxel.rasterization`;
- mesh/PBR/environment rendering resolves to the permissive renderer module.

Then load the complete pipeline:

```bash
python validate-pipeline.py
```

It should report:

- RTX 4090 as the pipeline device;
- default pipeline type `512`;
- no loaded component with `1024` in its name;
- `ZhengPeng7/BiRefNet` as the active background-removal model.

These checks complement the repository-wide compliance scan; they do not
replace it.

## Phase 15 — generate and validate a 512 asset

Use a simple, rights-cleared input with a plain background and a single,
well-separated object:

```bash
mkdir -p /external/trellis-tests

python example_512.py \
  --input /external/rights-cleared-inputs/test-object.png \
  --output /external/trellis-tests/test-object.glb
```

The example:

- loads `microsoft/TRELLIS.2-4B`;
- runs `pipeline_type="512"`;
- simplifies to about 500,000 faces;
- renders a 60-frame 512 px preview;
- exports a GLB with 2,048 px PBR textures.

Validate the result instead of accepting file existence as success:

```bash
python validate-glb.py /external/trellis-tests/test-object.glb
sha256sum /external/trellis-tests/test-object.glb
```

The validator checks:

- GLB magic, version, declared length, and JSON chunk;
- successful loading through `trimesh`;
- at least one mesh primitive;
- material presence;
- embedded texture/image presence.

### Observed acceptance results

Two controlled simple-image tests completed successfully:

| Input | Generation | Total run | GLB size | Faces | Materials | Textures | Peak CUDA allocated |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Red ceramic mug | 47.293 s | 125.55 s | 16,466,552 bytes | 498,169 | 1 | 2 | 2.658 GiB |
| Blue wooden rocket | 46.861 s | 97.329 s | 16,783,940 bytes | 497,092 | 1 | 2 | 2.622 GiB |

A final run through the permanent `example_512.py` path produced:

| Property | Result |
| --- | --- |
| Input subject | Red mug |
| Total time including preview/export | 162.28 s |
| GLB size | 16,366,528 bytes |
| Faces | 498,594 |
| Structure | 1 mesh, 1 primitive, 1 material, 2 textures, 2 images |
| Peak CUDA allocated/reserved | 2.658 / 2.799 GiB |
| SHA-256 | `ae6e1452a6dbed0b8311aaf56d019fe38015931f676e8a43ea5c868acdbdb309` |

The rocket was recognizable and coherent. The mug's silhouette, handle, and
colors were good, but the unseen/open top could be inferred incorrectly.
Single-image generation does not guarantee unseen geometry, watertight
topology, correct scale, game-ready orientation, or final art quality.
Blender cleanup and engine-side normalization may still be required.

These controlled test inputs and outputs were validation artifacts, not
production-approved game assets.

## Phase 16 — optional local interfaces

Run Gradio only after the CLI acceptance path succeeds:

```bash
source ~/.config/trellis2/env.sh
eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
conda activate trellis2
cd ~/ai/TRELLIS.2
python app.py
```

Keep the service bound to localhost unless authentication, firewalling, and
network exposure have been deliberately reviewed. Do not enable a public
share link on a machine holding private inputs or model credentials.

The UI is a convenience layer. Production provenance should be recorded by an
explicit post-generation command so no required rights field is silently
omitted.

## Phase 17 — permanent compliance infrastructure

The private repository is:

```text
https://github.com/FurkanTuzemen/impassable_games_assets
```

It is intentionally text-only and contains:

```text
tooling/       deterministic audit and provenance tools
compliance/    immutable, timestamped audit runs and evidence
provenance/    asset sidecars and a chained manifest
docs/          generated third-party license inventory
```

The tools use the Python standard library and must not install, upgrade, or
remove packages in the TRELLIS environment.

Run the full suite from WSL:

```bash
cd /mnt/c/Users/<windows-user>/impassable_games_assets

/home/<linux-user>/miniconda3/envs/trellis2/bin/python \
  tooling/run_compliance.py \
  --conda-exe /home/<linux-user>/miniconda3/bin/conda \
  --prefix /home/<linux-user>/miniconda3/envs/trellis2 \
  --python /home/<linux-user>/miniconda3/envs/trellis2/bin/python \
  --trellis-repo /home/<linux-user>/ai/TRELLIS.2 \
  --hf-cache /home/<linux-user>/.cache/huggingface/hub
```

Each invocation exclusively creates:

```text
compliance/YYYY-MM-DD/YYYYMMDDTHHMMSS.ffffffZ/
```

Never edit, delete, reuse, or overwrite a completed run. If a historical
finding is later resolved, archive new evidence in a new dated run and update
the forward-looking attestation. The old report remains an accurate record of
what was known at that time.

The orchestrator runs:

1. sorted conda and pip inventories plus a deterministic CycloneDX 1.6 SBOM;
2. exact Hugging Face cache revision and license-file verification;
3. package-license classification and license-document generation;
4. forbidden import, site-packages name, and license-text absence checks;
5. BiRefNet-default and `rembg` fallback configuration/hash/inference checks;
6. isolated provenance self-test and production-manifest validation.

### License policy

| Result | Policy |
| --- | --- |
| `ALLOWED` | MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC, Zlib, Unlicense, CC0-1.0, PSF-2.0 |
| `FLAGGED` | GPL, AGPL, LGPL, MPL families |
| `FORBIDDEN` | NonCommercial, CC BY-NC, NVIDIA Source Code License, research-only, non-commercial, evaluation-only |
| `UNKNOWN` | Evidence is absent, generic, conflicting, or insufficient |

The audit does not guess. `UNKNOWN` is a request for evidence, not a
convenient approval. A forbidden package makes `audit_licenses.py` exit
non-zero for CI use.

Human-resolved decisions live in `tooling/attestations.yaml`. An attestation
must include:

- package or artifact;
- exact version or revision;
- resolved license and decision;
- evidence URL and evidence type;
- date recorded;
- free-text note.

An attestation matches only its exact version/revision. BiRefNet's MIT
decision must therefore stop applying if its revision changes.

### Latest validated audit snapshot

The full run `20260729T184224.650052Z` passed with:

| Classification | Count |
| --- | ---: |
| Total packages | 153 |
| Allowed | 117 |
| Flagged | 13 |
| Forbidden | 0 |
| Unknown | 23 |

Its SBOM SHA-256 was:

```text
2d688f98d7020cd2b498becb1c78ce4e6f3dac2b35dcb2d28f52078a86d5a6a7
```

The absence gate passed after scanning 232 installed license files. The
`rembg` fallback inference also passed.

Current flagged packages were:

- `certifi 2026.7.22` — MPL-2.0;
- `easydict 1.13` — LGPL-3.0;
- `ld_impl_linux-64 2.46.1` — GPL-3.0-only;
- `libgcc`, `libgcc-ng`, `libgomp`, and `libstdcxx 16.1.0` —
  GPL-3.0-only with the GCC runtime exception where recorded;
- `libnsl 2.0.1` — LGPL-2.1-only;
- `libxcrypt 4.4.36` — LGPL-2.1-or-later;
- `orjson 3.11.9` — MPL-2.0 and an Apache-or-MIT alternative;
- `plyfile 1.1.5` — GPL;
- `readline 8.3` — GPL-3.0-only;
- `tqdm 4.70.0` — MPL-2.0 and MIT.

Current unknowns were:

- `bzip2`, `liblzma`, `libsqlite`, `llvmlite`, `ncurses`, `pillow`,
  `python-dateutil`, `regex`, `tk`, and `tokenizers`;
- NVIDIA CUDA 12 packages for cuBLAS, CUPTI, NVRTC, runtime, cuDNN, cuFFT,
  cuRAND, cuSOLVER, cuSPARSE, cuSPARSELt, NCCL, nvJitLink, and NVTX.

These labels reflect what the deterministic detector could prove from the
observed metadata and evidence. They do not mean that every unknown package
has restrictive terms. Resolve them with version-specific primary evidence,
never with a plausible guess. The report will change when the environment
changes, so always cite a run ID rather than copying these counts indefinitely.

## Phase 18 — record every production asset

First complete the input source and rights status. Both are mandatory:

```bash
cd /mnt/c/Users/<windows-user>/impassable_games_assets

/home/<linux-user>/miniconda3/envs/trellis2/bin/python \
  tooling/asset_provenance.py record \
  --asset /external/build/output/asset.glb \
  --storage-location s3://impassable-assets/production/asset.glb \
  --input-image /external/inputs/reference.png \
  --input-source "Created in-house by Impassable Games" \
  --input-rights-status "Owned by Impassable Games; approved for commercial use" \
  --sbom compliance/YYYY-MM-DD/RUN_ID/sbom.cyclonedx.json \
  --model-report compliance/YYYY-MM-DD/RUN_ID/model-checkpoints.json \
  --trellis-repo /home/<linux-user>/ai/TRELLIS.2 \
  --tool-version "TRELLIS.2-4B 512"
```

Use the real source and rights statement for the particular input. Do not copy
the example text if it is untrue.

The command records:

- asset filename, plain SHA-256, and AP11-compatible
  `sha256:<digest>` identifier;
- required external storage location;
- UTC ISO 8601 timestamp;
- tool version and exact TRELLIS implementation commit;
- source dirty state, diff hash, and untracked-source hashes;
- SBOM hash;
- exact model repositories, revisions, licenses, and evidence;
- input image SHA-256, source, and rights status.

It writes:

```text
provenance/assets/<filename>.<hash-prefix>.provenance.json
provenance/manifest.json
```

The manifest is append-only and SHA-256 chained. Validate it after recording:

```bash
/home/<linux-user>/miniconda3/envs/trellis2/bin/python \
  tooling/asset_provenance.py validate
```

Production recording should fail if:

- the source tree is dirty;
- rights fields are blank;
- storage is missing, local-only, credential-bearing, or a temporary signed
  URL;
- an exact checkpoint is absent;
- model-license evidence is unresolved.

Development override flags are allowed only for clearly labeled tests. The
successful 2026-07-29 test provenance was intentionally marked
non-production because the TRELLIS working tree was dirty.

Commit and push each evidence update. The remote server timestamp is an
additional independent record.

## Release-credit and asset-review checklist

Before a generated asset enters a commercial build:

- [ ] The private TRELLIS fork is at a reviewed, clean, pushed commit.
- [ ] The full compliance suite passed against that commit and environment.
- [ ] The SBOM and model report exist in an immutable run directory.
- [ ] `FORBIDDEN` is zero.
- [ ] Every relevant `UNKNOWN` and `FLAGGED` item was reviewed for the actual
      distribution boundary.
- [ ] Each model revision matches its evidence or exact attestation.
- [ ] BiRefNet remains on its attested revision, or a new review was completed.
- [ ] The DINOv3 credit requirement is in the game's final credits.
- [ ] The input image hash, source, and rights status are complete and true.
- [ ] The output was manually checked for third-party resemblance, trademarks,
      logos, recognizable characters, and protected product designs.
- [ ] The GLB passed structural validation and art/engine review.
- [ ] The binary is in stable external storage.
- [ ] The provenance sidecar and chained manifest entry match the binary.
- [ ] The text/JSON evidence commit was pushed to the private remote.

## Residual training-data risk

Removing or replacing dependencies does not change the data on which TRELLIS
and its supporting models were trained. TRELLIS documentation refers to large
3D corpora such as ObjaverseXL and sources that can include assets with
attribution terms. The legal treatment of model outputs, possible memorization,
and source-asset obligations remains fact-specific and unsettled.

Practical controls include:

- use simple, original, rights-cleared input images;
- avoid prompts or inputs targeting a named artist, franchise, product, or
  recognizable third-party asset;
- compare suspicious outputs with likely source material;
- require human art and rights review;
- retain hashes and evidence even for rejected assets;
- consult counsel for the final commercial policy.

A hosted provider may sometimes reduce business risk if its current contract
provides explicit commercial rights or indemnity. That is a contractual
benefit, not proof that the underlying technical risk is zero, and the
provider's current terms must be reviewed at the time of use.

## Troubleshooting

### `nvidia-smi` works in Windows but not WSL

1. Update WSL with `wsl --update`.
2. Shut it down with `wsl --shutdown`.
3. Confirm the distribution is version 2.
4. Reinstall/update the Windows NVIDIA WSL-capable driver.
5. Do not install a Linux NVIDIA driver in Ubuntu.

### `nvcc` is not found

```bash
source ~/.config/trellis2/env.sh
/usr/local/cuda-12.4/bin/nvcc --version
```

If the absolute path is missing, verify `cuda-toolkit-12-4` with `dpkg -l`.

### PyTorch sees no CUDA

Confirm the environment has a `+cu124` build rather than a CPU wheel:

```bash
python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"
```

Recheck `LD_LIBRARY_PATH`, the WSL driver bridge, and the active conda
environment.

### Hugging Face returns 401 or 403

```bash
hf auth whoami
```

Confirm the account accepted any gated-model terms and that the token has read
access. Re-run `hf auth login` interactively. Do not expose the token while
debugging.

### WSL asks for a password

It wants the Linux user's `sudo` password, not the Hugging Face token or the
Windows password. Reset it through the root command in Phase 2 if necessary.

### DINO fails with a missing `.layer`

Verify the exact Transformers version and the dual-layout compatibility code
in `image_feature_extractor.py`. Do not downgrade blindly without producing a
new SBOM and audit.

### EXR loading fails

Use `EnvMap.from_file` with the explicit PNG fallback. An environment variable
cannot add a decoder that the installed wheel does not contain.

### Code tries to import `nvdiffrast`

The patched source or installed `o-voxel` copy is incomplete. Compare hashes,
reinstall `o-voxel` from the private implementation commit, and rerun both
absence checks. Do not install `nvdiffrast` as a shortcut.

### BiRefNet cannot be accessed

Select the locally installed `rembg_u2net` backend, confirm the U²-Net model
hash, and run the fallback inference check. A production run that changes
backend must record that fact in provenance.

### Generation runs out of VRAM

- verify that only the 512 components are loaded;
- close other GPU applications;
- keep `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`;
- restart the Python process between heavy runs;
- reduce preview/export work before changing the core model profile.

The validated core run used less than 3 GiB of peak PyTorch allocations, but
model/runtime reporting does not always include every driver and extension
allocation.

### The GLB exists but looks wrong

Run `validate-glb.py` first. If structurally valid, inspect:

- input segmentation and alpha;
- camera/view assumptions;
- unseen geometry hallucination;
- normals, scale, and orientation;
- material channel interpretation;
- Blender and game-engine import settings.

Structural validity and art quality are separate gates.

### Provenance refuses a dirty tree

That is intentional. Review the diff, commit it to the private TRELLIS fork,
push it, rerun compliance, and then generate/record the production asset.
Do not use the development override to make a production failure disappear.

## Updating without losing reproducibility

Do not upgrade the production environment in place.

For a proposed CUDA, PyTorch, Transformers, extension, model, or TRELLIS
change:

1. create a new conda environment or a new WSL test distribution;
2. pin the candidate source and model revisions;
3. apply the implementation from a reviewed branch;
4. run installation, absence, pipeline, fallback, generation, GLB, license,
   and provenance tests;
5. compare output quality and deterministic evidence;
6. resolve every new unknown/flagged/forbidden result;
7. merge and tag only after review;
8. keep the old environment until the replacement is accepted.

Never reuse a license attestation for a different version or revision.
Never rewrite a previous compliance run to make a new version appear approved.

## Rebuild acceptance criteria

A rebuild is complete only when all of these are true:

- [ ] Ubuntu 22.04 runs under WSL 2.
- [ ] Windows `nvidia-smi` and WSL `nvidia-smi` see the RTX 4090.
- [ ] CUDA Toolkit 12.4 is installed without a Linux display driver.
- [ ] PyTorch reports CUDA 12.4 and completes a real GPU operation.
- [ ] The private TRELLIS source is clean and at a pushed commit.
- [ ] PyTorch3D and all native extensions are at recorded commits.
- [ ] `nvdiffrast`, `nvdiffrec`, and `nvdiffrec_render` are absent.
- [ ] No installed license file contains NVIDIA Source Code License text.
- [ ] BiRefNet uses the exact attested revision.
- [ ] `rembg`/U²-Net fallback inference passes.
- [ ] All required checkpoint revisions and license evidence verify.
- [ ] Only the 512 pipeline components load.
- [ ] The DINO compatibility test returns finite CUDA features.
- [ ] A simple rights-cleared image produces a textured GLB.
- [ ] The GLB structure, material, and textures validate.
- [ ] A new full compliance run passes with zero forbidden packages.
- [ ] Production provenance records without any development exception.
- [ ] The evidence commit is pushed to the private remote.

## Durable work still to complete

The workstation works, but these steps are necessary to make a future rebuild
fully mechanical:

1. Create a private TRELLIS.2 fork.
2. Commit and push the current renderer, rasterizer, background-removal,
   512-only, DINO, EXR, validation, and example changes.
3. Make every model-loading call revision-pinned or exact-snapshot/offline.
4. Record the private implementation commit in a fresh compliance run.
5. Regenerate the final acceptance asset from the clean commit.
6. Record it without a dirty-tree development exception.
7. Optionally turn this document into idempotent bootstrap scripts only after
   the private implementation commit exists; otherwise automation would still
   be missing its most important input.

## Primary references

- [Microsoft TRELLIS.2 repository](https://github.com/microsoft/TRELLIS.2)
- [NVIDIA CUDA on WSL user guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)
- [Microsoft WSL installation guide](https://learn.microsoft.com/windows/wsl/install)
- [PyTorch3D pinned BSD-3-Clause license](https://github.com/facebookresearch/pytorch3d/blob/33824be3cbc87a7dd1db0f6a9a9de9ac81b2d0ba/LICENSE)
- [BiRefNet maintainer clarification, issue #316](https://github.com/ZhengPeng7/BiRefNet/issues/316#issuecomment-5120372022)
- [DINOv3 model repository](https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m)
- [TRELLIS.2-4B model repository](https://huggingface.co/microsoft/TRELLIS.2-4B)
