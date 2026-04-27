# Hello-world example rule.
#
# Demonstrates the three things every rule in this template needs:
#   1. params.docker = docker_run("<image>") — expands to `docker run ...` in
#      local Docker mode, empty otherwise.
#   2. container: get_container_path("<image>", use_apptainer=USE_APPTAINER)
#      — Snakemake uses this in Apptainer mode; ignored under Docker.
#   3. {output.<name>} / {wildcards.<name>} templating in the shell block.
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
        message=_hello_message,
    container:
        get_container_path("hello", use_apptainer=USE_APPTAINER)
    benchmark:
        "{output_dir}/benchmarks/{sample}/hello.tsv"
    shell:
        "{params.docker} sh -c 'echo \"Sample {wildcards.sample} says: {params.message}\" > {output.greeting}'"
