"""Validate cookiecutter inputs before the project is generated."""
import re
import sys

SLUG_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

project_slug = "{{ cookiecutter.project_slug }}"
author_email = "{{ cookiecutter.author_email }}"
notification_email = "{{ cookiecutter.notification_email }}"
docker_username = "{{ cookiecutter.docker_username }}"
python_version = "{{ cookiecutter.python_version }}"

errors = []

if not SLUG_PATTERN.match(project_slug):
    errors.append(
        f"project_slug {project_slug!r} is invalid. "
        "Must start with a letter or digit and contain only letters, "
        "digits, hyphens, or underscores."
    )

for label, value in (("author_email", author_email), ("notification_email", notification_email)):
    if not EMAIL_PATTERN.match(value):
        errors.append(f"{label} {value!r} does not look like an email address.")

if not docker_username or docker_username == "your-dockerhub-user":
    print(
        "Note: docker_username left at the default 'your-dockerhub-user'. "
        "You can still run the hello-world example with the public alpine "
        "fallback baked into test_config.yaml.",
        file=sys.stderr,
    )

if not re.match(r"^3\.\d{1,2}$", python_version):
    errors.append(f"python_version {python_version!r} must look like '3.11', '3.12', etc.")

if errors:
    print("\n".join(f"ERROR: {e}" for e in errors), file=sys.stderr)
    sys.exit(1)
