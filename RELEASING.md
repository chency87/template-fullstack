# Releasing The Template

This template repo uses Git tags so generated projects can record a stable Copier ref instead of falling back to `HEAD`.

## Local release flow

1. Run the smoke tests:

   ```sh
   bash test.sh
   ```

2. Create an annotated tag:

   ```sh
   git tag -a v0.1.0 -m "Release v0.1.0"
   ```

3. Push the branch and tag:

   ```sh
   git push origin main
   git push origin v0.1.0
   ```

After the first pushed tag, Copier will stop warning that no git tags were found when users scaffold from the tagged template.

## GitHub Actions release flow

If you prefer GitHub Actions:

1. Open `Actions` in GitHub.
2. Run the `Release Template` workflow.
3. Enter a semantic version like `v0.1.0`.

That workflow runs `bash test.sh`, creates the tag, pushes it, and opens a GitHub release with generated notes.
