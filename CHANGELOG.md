# Changelog

All notable changes to this template. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are git tags
(`cookiecutter gh:gladstone-institutes/snakemake-hpc-template --checkout v0.2.0`).
Each generated project records the template version it came from in its own
`CHANGELOG.md`.

## [0.2.0] - 2026-09-04

### Changed

- `workflow/test_pipeline.sh` is now `workflow/pipeline.sh`: it runs, builds, and
  downloads as well as tests.
- Docker runs as the invoking user by default (`execution.docker_run_as_user: true`,
  with `HOME=/workspace`), so outputs are never root-owned on Linux hosts.
- `config_corehpc.yaml.example` points the hello image at the public `library/bash:5`
  image, so the CoreHPC setup checklist runs before any image is built.
- Docs rewritten for readers new to containers: shorter, plain language, one home per
  fact, and a container lifecycle diagram (`docs/containers.svg`).

### Added

- `project_root` config key: the single storage path in a cluster config. Relative
  `output_dir` and `containers.dir` resolve under it, `launch.sh` keeps caches in
  `<project_root>/.cache`, and it is bound into both container runtimes. One
  implementation in `workflow/scripts/config_paths.py`.
- CoreHPC setup checklist in `docs/PIPELINE.md`: prove the untouched template runs on
  the cluster before wiring in scripts.
- "Why Docker builds" section: one Dockerfile for both runtimes, Docker Hub private
  image limits, any registry via a prefix in `user:`.
- "Writing the Dockerfile" advice in `AGENTS.md` for images that behave the same under
  Docker and Apptainer.
- Documented CoreHPC scratch layout: `/mnt/scratch` is shared, `/tmp` is node-local
  inside a job.
- Template version stamped into the generated project's `CHANGELOG.md`
  (`_template_version` in `cookiecutter.json`, kept in sync by the bake tests).

## [0.1.0] - 2026-09-03

### Added

- Initial release: a Snakemake + uv pipeline for UCSF CoreHPC (Slurm, GPU validated)
  and local Docker or Apptainer, with the `launch.sh` driver-job launcher, image
  pre-pull, per-rule resources in config, resource calibration from benchmarks, and a
  deprecated but working Wynton SGE profile.

[0.2.0]: https://github.com/gladstone-institutes/snakemake-hpc-template/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gladstone-institutes/snakemake-hpc-template/releases/tag/v0.1.0
