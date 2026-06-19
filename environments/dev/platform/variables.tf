variable "argocd_repo_pat" {
  description = "GitHub PAT with read access to agora-helm (used by ArgoCD to pull chart updates)"
  type        = string
  sensitive   = true
}
