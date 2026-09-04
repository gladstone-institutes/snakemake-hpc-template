# AGENTS.md - wiring scripts into {{ cookiecutter.project_name }}

Guidance for coding agents helping a user turn their **existing analysis scripts**
(R / Python / bash) into Snakemake rules in this pipeline. Read this first, then
`workflow/rules/hello.smk` (the canonical rule) and `docs/PIPELINE.md` (full operational
detail: building containers, clusters, GPU, troubleshooting).

## Mental model (read first)

A Snakemake rule is **inputs -> command -> outputs**, parameterized by sample wildcards.
This pipeline has a few deliberate conventions you must follow:

- **Containers run via shell prefixes, not the `container:` directive.** Every rule
  prepends `{params.docker}{params.apptainer}` to its `shell:`. Exactly one expands per
  run mode (`docker run ...` locally, `apptainer exec ...` on HPC); the other is `""`.
  The concept is explained in `docs/PIPELINE.md` under "Containers in one minute".
- **Resources are config-driven.** Every rule needs an entry under `resources:` in
  `workflow/config/config.yaml` (`threads` / `mem_gb` / `runtime_min`, optional
  `scratch_gb`). `_threads("rule")` and `_resources("rule", gpu=...)` translate these to
  Slurm (or deprecated SGE) keys based on the active profile. A missing entry is a
  `KeyError` at parse.
- **One Snakefile, four modes.** The same rules run as local Docker, local Apptainer,
  CoreHPC Slurm (+ GPU), and deprecated Wynton SGE. You write a rule once; the profile +
  config pick the mode. Don't special-case modes inside a rule. **CoreHPC Slurm is the
  supported cluster path**; target it unless the user says they are on Wynton.
- **Scripts live in `workflow/scripts/`** and are invoked from a rule's `shell:` —
  **declared as an `input:`** via `script=script_path("my_step.R")` and called as
  `{input.script}`. Snakemake's `code` rerun trigger only tracks the rule's own shell
  directive, not the external file it calls, so without this an edited script silently
  reuses stale outputs.
- **Every rule writes a persistent log**, `{output_dir}/logs/{rule}/{wildcards}.log`, via
  `... 2>&1 | tee {log}`. The scheduler's own job logs are transient (the Slurm executor
  deletes them on success); this is the record that survives. `set -euo pipefail` is
  Snakemake's default shell, so a failing script still fails the job through the pipe.

The helpers above all live in `workflow/rules/common.smk`
(`docker_run`, `apptainer_run`, `script_path`, `_threads`, `_resources`,
`_resources_sized`, `_runtime_min_scaled`, `gpu_sampler_prefix`, `load_samples`,
`get_all_samples`).

## Gather these from the user first

You cannot write a correct rule from a script alone. For **each** script the user wants
to add, get answers to the following. The right-hand side is what each answer determines.

- **Inputs and outputs** - which files does it read, which does it produce (exact paths /
  names)? -> the rule's `input:` and `output:`.
- **Granularity** - does it run once per sample, once across all samples (aggregate), or
  once per some other grouping (batch / condition / contrast)? -> the wildcards, and
  whether its output is requested in `rule all` via `expand(...)`.
- **Invocation** - how is it run today? The exact command: interpreter (`Rscript` /
  `python` / `bash`) and the positional / flag argument order. -> the `shell:` line.
- **Pipeline order** - which script's outputs feed which? -> the DAG. A downstream rule's
  `input:` is the upstream rule's `output:`; Snakemake infers run order from that.
- **Environment** - language plus packages and system tools. Is there an existing image,
  a `Dockerfile`, a conda env, or just "works on my machine"? -> reuse an image vs
  build a new one under `workflow/containers/<name>/`.
- **Per-sample parameters** - does the script need sample-specific values (input paths,
  group labels, thresholds)? -> new columns in `workflow/config/samples.tsv`.
- **Global parameters** - tunable constants (reference genome path, cutoffs)? -> entries
  in `config.yaml`, read in the rule via `config[...]`.
- **Resources** - threads, memory (GB), expected runtime (minutes), GPU? scratch space?
  -> the rule's entry under `resources:` in `config.yaml`.
- **Data and filesystem** - where do raw inputs live on the target system? Is that a
  shared filesystem outside the working dir that Apptainer must be told to bind? ->
  `output_dir`, `samples`, and `containers.bind_paths` in the cluster config.
- **Hardcoded assumptions** - absolute paths, reliance on a specific working directory,
  hardcoded output names baked into the script -> these must be parameterized to take
  arguments so the rule controls them.
- **Target environment** - laptop Docker, CoreHPC Slurm, GPU (or deprecated Wynton
  SGE)? -> which profile, and whether the image must be pushed to a registry first
  (required before any HPC run, since Apptainer pulls the `.sif` from there).

If the user can't answer some of these, ask narrowing questions or inspect the script,
but do not guess inputs / outputs or resources silently. State assumptions you make.

## Wiring procedure

1. **Inventory and sketch the DAG.** List the scripts, ask the questions above, and
   write down which outputs feed which so you know the rule chain before writing code.
2. **Decide the container per tool.** Either reuse a suitable public image, or scaffold a
   new one (built with Docker only; see "Why Docker builds" in `docs/PIPELINE.md`): `mkdir workflow/containers/<name>`, add a `Dockerfile` with
   `LABEL version="X.Y.Z"` (the single source of truth for the tag), copy
   `workflow/containers/hello/build.sh` into it and set `IMAGE=`, then register the image
   under `containers.images.<name>` in both `config.yaml` and `test_config.yaml`. The
   image must contain `bash` (Apptainer wraps every rule shell in `bash -c '...'`). See
   "Building your own container" in `docs/PIPELINE.md`.
3. **Place the script** at `workflow/scripts/<name>.{R,py,sh}`. Parameterize any
   hardcoded paths so it reads inputs / writes outputs from its command-line arguments.
4. **Write the rule** at `workflow/rules/<name>.smk`, copying `hello.smk`'s shape:
   ```python
   rule my_step:
       input:
           data="{output_dir}/{sample}/upstream.tsv",   # or raw input paths
           script=script_path("my_step.R"),             # so script edits rerun the rule
       output:
           result="{output_dir}/{sample}/my_step.tsv",
       params:
           docker=docker_run("mytool"),
           apptainer=apptainer_run("mytool", gpu=False),
       threads: _threads("my_step")
       resources:
           **_resources("my_step", gpu=False),
       benchmark:
           "{output_dir}/benchmarks/{sample}/my_step.tsv"
       log:
           "{output_dir}/logs/my_step/{sample}.log",
       shell:
           "{params.docker}{params.apptainer} Rscript {input.script} "
           "{input.data} {output.result} 2>&1 | tee {log}"
   ```
   The interpreter call goes **inside** `shell:` so the container prefix wraps it.
5. **Add the resources entry** under `resources:` in `config.yaml`
   (`threads` / `mem_gb` / `runtime_min`, optional `scratch_gb`).
6. **Wire it into the Snakefile:** add `include: "rules/<name>.smk"` and extend `rule all`
   to request the new final outputs via `expand(...)` over `get_all_samples()`.
7. **Add any per-sample columns** to `samples.tsv` and read them in the rule with a small
   input function: `samples.loc[wildcards.sample, "<col>"]` (see `_hello_message` in
   `hello.smk`). Add any global params to `config.yaml` and read via `config[...]`.
8. **Remove the hello example** once real rules exist: delete `rules/hello.smk`,
   `workflow/scripts/hello.sh`, its `include:`, the `hello` entry under `resources:`, the
   `hello` container, and the `message` column if no rule uses it.

## Conventions and gotchas

- **DO** copy `hello.smk` exactly: both the `docker` and `apptainer` params, `_threads`,
  `**_resources`, and a `benchmark:`.
- **DON'T** use Snakemake's `container:` directive or `software-deployment-method` - this
  template deliberately doesn't, and reintroducing them breaks the CoreHPC / GPU model.
- **DON'T** use the `script:` or `run:` directives for steps that need a container - they
  execute on the host and bypass `docker_run` / `apptainer_run`. Wrap the interpreter in
  `shell:` instead.
- **Every rule needs a `config["resources"]` entry**, or `_threads` / `_resources` raise
  `KeyError`. The initial numbers are guesses; after a run, replace them with what the
  `benchmark:` files measured:
  `uv run python workflow/scripts/calibrate_resources.py --output_dir <output_dir>`.
- **Size-aware runtime** for a rule whose wall time scales with a per-sample quantity:
  add `runtime_base_min` / `runtime_per_size_min` to its config entry and use
  ```python
   resources:
       **_resources_sized("my_step"),
       runtime=lambda wildcards: _runtime_min_scaled("my_step", wildcards.sample),
  ```
  `runtime_min` then acts as the CAP — set it to the partition MaxTime, because a Slurm
  request above MaxTime is accepted and then pends forever as `(PartitionTimeLimit)`
  rather than erroring.
- **Expose size/count thresholds as config, don't hardcode them.** A threshold tuned for
  production (minimum donors, minimum group size, a k grid) makes a small test fixture
  cover *nothing* while still reporting success — or, worse, errors on an empty
  intermediate far downstream. Put the threshold in `config.yaml`, shrink it in the test
  config, and make the consumer tolerate the empty result. Fix the class of problem, not
  the one instance that broke.
- **Read a sample sheet via `params:`, never declare it as an `input:`.** As an input, any
  `git pull` that bumps its mtime reruns every rule that depends on it, forever.
- **Anything a tool writes that you did not declare as an output is never cleaned up** by
  Snakemake — cache and checkpoint directories especially. If the tool then refuses to
  reuse a checkpoint written under a different configuration, that guard is correct: delete
  the stale directory by hand rather than working around it.
- **Declare every output** the script writes; Snakemake only tracks declared outputs and
  removes them on failure to keep state consistent.
- Use `{wildcards.sample}` for per-sample paths. An **aggregate** rule takes a list input
  built in an input function, e.g.
  `expand("{out}/{sample}/my_step.tsv", out=config["output_dir"], sample=get_all_samples())`,
  and produces a single combined output.
- For shared filesystems on HPC, add their paths to `containers.bind_paths` so Apptainer
  can see them inside the container.
- **GPU** (CoreHPC Slurm is the only validated GPU path): pass `gpu=True` to **both**
  `apptainer_run(...)` and `_resources(...)`, and optionally prepend
  `gpu_sampler_prefix(...)` to log nvidia-smi utilization. See the GPU recipe in
  `hello.smk`'s header comment and `workflow/profiles/slurm/README.md`.
- Bump the image `tag:` in `config.yaml` whenever you bump the Dockerfile `LABEL version`,
  or the pipeline silently runs the old image. After `build.sh --push`, **verify the tag
  actually landed on the registry** (`docker manifest inspect <user>/<img>:<tag>`) — a
  cluster run pulls from there, and a missing tag surfaces as a confusing pull failure
  hours later.
- **End every Dockerfile with a verification `RUN`** that imports/loads each package the
  rules need (and asserts the base image version, if you build `FROM` your own image).
  A failed install otherwise ships silently and fails inside a cluster job instead.
- **Pre-pull images before a cluster run**: `uv run ./workflow/test_pipeline.sh prepull`
  (or `./workflow/launch.sh <scope> prepull`) on the login node. Compute nodes usually
  have no outbound internet, so the `onstart` auto-pull cannot reach the registry from a
  submitted job.

## Verify your work

```bash
uv run ./workflow/test_pipeline.sh dry-run    # DAG resolves; no resources KeyError
uv run ./workflow/test_pipeline.sh lint       # snakemake lint
uv run ./workflow/test_pipeline.sh run        # end-to-end, if Docker is available
```

Outputs land under `.tests/integration/results/<sample>/`. Adjust
`workflow/config/test_samples.tsv` to exercise your rule. Before any real cluster submit,
run `dry-run-slurm` (or `dry-run-sge` on the deprecated Wynton path) to confirm the DAG
and resource translation.

Once the pipeline has real steps, add a third tier between `dry-run` (no data) and a
production run: a **smoke config** (`workflow/config/smoke_config.yaml`) that runs the
whole DAG on a tiny committed fixture with every threshold shrunk. A dry-run only proves
the DAG resolves; the smoke proves the scripts actually run and their outputs chain.
That is what the config-driven-thresholds rule above is for.

## Pointers

- `workflow/rules/hello.smk` - the canonical rule shape (copy it).
- `workflow/rules/common.smk` - the helpers every rule uses.
- `docs/PIPELINE.md` - full operational guide (containers, build / push, clusters, GPU,
  adding rules and containers).
- `workflow/profiles/slurm/README.md` - CoreHPC Slurm + GPU specifics, the driver-job
  pattern, and the cluster gotchas that cost real debugging.
- `workflow/launch.sh` - submit a cluster run as a Slurm driver job (login shells are
  reaped when SSH drops; the slurm README explains).
