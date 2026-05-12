# Skill Lab — GitOps Deployment Config

This repo contains ArgoCD application definitions and environment values for Skill Lab.

## Structure

```
apps/
└── skill-lab-app/
    └── production/
        ├── application.yaml   # ArgoCD Application definition
        └── values.yaml        # Helm values (image tag updated by CI)
```

## How it works

1. CI in `my-skill-lab/SkillForge` builds Docker + Helm and pushes to Fly
2. The `gitops-deploy-production-skill-lab-app` action updates `image.tag` in `values.yaml`
3. ArgoCD detects the change and syncs production to the new version

## Manual update

```bash
# Update the image tag
sed -i 's/tag: ".*"/tag: "1.0.15"/' apps/skill-lab-app/production/values.yaml
git commit -am "Deploy 1.0.15 to production"
git push
# ArgoCD auto-syncs
```
