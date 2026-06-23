# Hello-world example rule.
#
# Demonstrates the shape every rule in this template follows:
#   1. params.docker     = docker_run("<image>")             — `docker run ...`
#      prefix in local Docker mode, "" otherwise.
#   2. params.apptainer  = apptainer_run("<image>", gpu=...) — `apptainer exec
#      ...` prefix in Apptainer/HPC mode, "" otherwise. Exactly one of docker /
#      apptainer expands per run mode; in host mode both are "".
#   3. threads:   _threads("<rule>")          — from config["resources"][rule].
#      resources: **_resources("<rule>", gpu) — translated to SGE/Slurm keys by
#      the active profile's scheduler. Every rule needs a config["resources"]
#      entry (see workflow/config/config.yaml).
#   4. {output.<name>} / {wildcards.<name>} templating in the shell block.
#
# GPU rules (CoreHPC Slurm): pass gpu=True to BOTH apptainer_run and _resources,
# and optionally prepend gpu_sampler_prefix(...) to log nvidia-smi utilization:
#
#   params:
#       docker=docker_run("mytool"),
#       apptainer=apptainer_run("mytool", gpu=True),
#       gpu_sampler=lambda w, output: gpu_sampler_prefix(
#           Path(output.result).parent, "mygpurule", gpu=True),
#   resources:
#       **_resources("mygpurule", gpu=True),
#   shell:
#       "{params.gpu_sampler}{params.docker}{params.apptainer} mytool ..."
#
# Replace this file with your real rules and remove `include: "rules/hello.smk"`
# from workflow/Snakefile.


def _hello_message(wildcards):
    return samples.loc[wildcards.sample, "message"]


rule hello:
    """Write a per-sample greeting drawn from the samples TSV."""
    output:
        greeting="{output_dir}/{sample}/hello.txt",
    params:
        docker=docker_run("hello"),
        apptainer=apptainer_run("hello", gpu=False),
        message=_hello_message,
    threads: _threads("hello")
    resources:
        **_resources("hello", gpu=False),
    benchmark:
        "{output_dir}/benchmarks/{sample}/hello.tsv"
    shell:
        "{params.docker}{params.apptainer} sh -c 'echo \"Sample {wildcards.sample} says: {params.message}\" > {output.greeting}'"
