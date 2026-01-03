#!/bin/bash
# =============================================================================
# git_setup.sh - Initialize git repo for nosofs.v3.7.0 with UFS integration
# =============================================================================
#
# This script sets up a git repository tracking only the essential files:
# - Shell scripts (ush/, scripts/, jobs/)
# - Python scripts (ush/pysh/)
# - Configuration templates (fix/secofs/*.template)
# - Control files (fix/secofs/secofs.ctl)
# - Documentation (*.md)
#
# Excludes: executables, large fix files, test outputs, logs
#
# Usage:
#   cd /path/to/nosofs.v3.7.0
#   ./git_setup.sh
#
# =============================================================================

set -e

echo "============================================"
echo "nosofs.v3.7.0 Git Repository Setup"
echo "============================================"

# Check if already a git repo
if [ -d ".git" ]; then
    echo "WARNING: .git directory already exists!"
    read -p "Remove and reinitialize? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Aborted."
        exit 1
    fi
    rm -rf .git
fi

# Initialize git repo
echo ""
echo "Step 1: Initializing git repository..."
git init

# Add .gitignore
echo ""
echo "Step 2: Adding .gitignore..."
git add .gitignore

# Add workflow directories (these are not in .gitignore)
echo ""
echo "Step 3: Adding workflow scripts..."
git add ecf/
git add jobs/
git add parm/
git add pbs/
git add scripts/
git add versions/

# Add ush scripts
echo ""
echo "Step 4: Adding ush scripts..."
git add ush/*.sh
git add ush/pysh/*.py

# Force-add UFS templates from fix/secofs (normally ignored)
echo ""
echo "Step 5: Force-adding UFS templates from fix/secofs..."
git add -f fix/secofs/secofs.ctl
git add -f fix/secofs/ufs.configure
git add -f fix/secofs/model_configure.template
git add -f fix/secofs/datm_in.template
git add -f fix/secofs/datm.streams.template

# Add documentation
echo ""
echo "Step 6: Adding documentation..."
git add *.md 2>/dev/null || true
git add -f secofs_test_run/outputs_06z/esmf_mesh/SECOFS_UFS_COASTAL_TRANSITION.md 2>/dev/null || true

# Add this setup script
git add git_setup.sh

# Show status
echo ""
echo "============================================"
echo "Files staged for commit:"
echo "============================================"
git status --short

# Count files
echo ""
echo "============================================"
echo "Summary:"
echo "============================================"
echo "Total files staged: $(git status --short | wc -l)"
echo ""

# Prompt for initial commit
read -p "Create initial commit? (y/n): " do_commit
if [ "$do_commit" == "y" ]; then
    git commit -m "Initial commit: nosofs.v3.7.0 with UFS-Coastal integration

Key additions for UFS-Coastal/DATM transition:
- nos_ofs_create_esmf_mesh.sh: ESMF mesh generation
- nos_ofs_gen_ufs_config.sh: UFS config file generator
- proc_scrip.py: Python SCRIP grid generator (replaces NCL)
- modify_gfs_4_esmfmesh.py: GFS CF-compliance modifier
- modify_hrrr_4_esmfmesh.py: HRRR CF-compliance modifier
- UFS templates: ufs.configure, model_configure.template, datm_in.template, datm.streams.template
- SECOFS_UFS_COASTAL_TRANSITION.md: Transition documentation

Integrated into nos_ofs_create_forcing_met.sh workflow
Enable with GENERATE_ESMF_MESH=true in secofs.ctl
"
    echo ""
    echo "Initial commit created!"
fi

echo ""
echo "============================================"
echo "Git setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Add remote: git remote add origin <your-repo-url>"
echo "  2. Push: git push -u origin main"
echo ""
