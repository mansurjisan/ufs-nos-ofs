#!/bin/bash
# fix_all_pbs_files.sh

cd /lfs/h1/nos/estofs/noscrub/mansur.jisan/packages/nosofs.v3.7.0/pbs

echo "Updating all SECOFS PBS files..."

# Define the replacements
OLD_USER="machuan.peng"
NEW_USER="mansur.jisan"
OLD_PATH="/lfs/h1/nos/nosofs/noscrub"
NEW_PATH="/lfs/h1/nos/estofs/noscrub"

# Update all jnos_secofs_*.pbs files
for file in jnos_secofs_*.pbs; do
    if [ -f "$file" ]; then
        echo "Updating $file..."
        # Create backup
        cp "$file" "${file}.backup"
        
        # Replace username
        sed -i "s/${OLD_USER}/${NEW_USER}/g" "$file"
        
        # Replace path
        sed -i "s|${OLD_PATH}|${NEW_PATH}|g" "$file"
        
        echo "  ✓ Updated $file"
    fi
done

echo -e "\n=== Verification ==="
echo "Checking for remaining old references..."

echo -e "\nFiles still containing 'machuan.peng':"
grep -l "machuan.peng" jnos_secofs_*.pbs 2>/dev/null || echo "  None found ✓"

echo -e "\nFiles still containing '/lfs/h1/nos/nosofs/noscrub':"
grep -l "/lfs/h1/nos/nosofs/noscrub" jnos_secofs_*.pbs 2>/dev/null || echo "  None found ✓"

echo -e "\nDone! Backups created with .backup extension"
