# ─────────────────────────────────────────────
#  ECR — container registry
# ─────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = "MUTABLE" # allows re-pushing :latest

  image_scanning_configuration {
    scan_on_push = true
  }

  # Delete all images when the repo is destroyed (safe for dev)
  force_delete = true
}

# Keep only the 5 most recent images to control storage costs
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ─────────────────────────────────────────────
#  Docker image — build locally & push to ECR
#
#  The kreuzwerker/docker provider handles:
#    1. docker build  (from python-streaming/Dockerfile)
#    2. docker tag
#    3. docker push   (authenticated via provider block in versions.tf)
#
#  triggers force a rebuild+push whenever the Dockerfile or app source files change.
# ─────────────────────────────────────────────

resource "docker_image" "app" {
  name = "${aws_ecr_repository.app.repository_url}:latest"

  build {
    context    = "${path.module}/.."
    dockerfile = "Dockerfile"

    # Target platform — Lambda always runs on x86_64
    platform = "linux/amd64"

    # IMPORTANT: BuildKit (used by Docker Desktop) adds OCI provenance
    # attestations by default. Lambda only supports Docker schema v2 manifests,
    # not OCI image index manifests. Setting provenance = "false" disables
    # the attestation and produces a plain Docker schema v2 image Lambda accepts.
    provenance = "false"

    # Also disable SBOM attestation for the same reason
    sbom = "false"
  }

  # Rebuild when source files change
  triggers = {
    dockerfile = filesha256("${path.module}/../Dockerfile")
    main_py    = filesha256("${path.module}/../main.py")
    reqs       = filesha256("${path.module}/../requirements.txt")
  }

  depends_on = [aws_ecr_repository.app]
}

resource "docker_registry_image" "app" {
  name          = docker_image.app.name
  keep_remotely = true   # don't delete from ECR when Terraform destroys this resource

  triggers = {
    image_id = docker_image.app.image_id
  }
}
