Release Management
==================

Pushing a tag will trigger a CurseForge build/release as well as a GitHub action which will create a GitHub release.

BigWigs packager is being used for GitHub actions.

Example Workflow
----------------

```
# Update the addon
vim core.lua

# Push changes to github
git add .
git commit -m "Updated [foo] and [bar]"
git push

# Tag and push to trigger actual releases
git tag v9.2.0-alpha-03
git push --tags
```
