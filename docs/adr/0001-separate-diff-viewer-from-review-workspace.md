# Separate the diff viewer from the review workspace

VSVim needs one integrated review experience while keeping its plugins usable
independently. SCM owns review sessions, agent-follow coordination, host
integration, and CRP state; a separately installable diff plugin owns comparison
presentation and reading position. This avoids tying the viewer to Codex or
GitHub, without introducing a separate package for every review feature;
CRP's implementation starts inside SCM while its specification stays independent.
