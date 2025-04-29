# Migrating to UV Workspace Packages

This document outlines the changes needed to migrate both the existing `aider_analytics.py` script and the `montaigne` module to dedicated workspace packages using UV workspace management.

## Overview

The current `aider_analytics.py` script will be moved to a dedicated package under the `packages/` directory, following the same workspace pattern used by the existing `montaigne` and `cicero` packages. The commit detection logic will be simplified to rely solely on the presence of a colon in the commit message to distinguish between human and AI (aider) commits.

## Changes Required

### 1. Create Directory Structure

Create the following directory structure:

```
packages/
  aider_analytics/
    pyproject.toml
    src/
      aider_analytics/
        __init__.py
        main.py
```

### 2. Create Package Configuration Files

#### `packages/aider_analytics/pyproject.toml`

```toml
[project]
name = "aider-analytics"
version = "0.1.0"
description = "Analytics tool for distinguishing between human and AI commit patterns"
authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
requires-python = ">=3.11,<3.12"
dependencies = [
    "click==8.1.8",
    "matplotlib>=3.5.0",
]

[project.scripts]
aider-analytics = "aider_analytics.main:main"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[tool.ruff]
line-length = 88
select = ["E", "F", "W", "I", "N", "C4", "UP", "ARG", "B"]
ignore = ["B008"]

[tool.ruff.format]
quote-style = "double"
```

#### `packages/aider_analytics/src/aider_analytics/__init__.py`

```python
"""
Analytics tool for distinguishing between human and AI commit patterns.
"""

__version__ = "0.1.0"
```

### 3. Move and Update Script Content

#### `packages/aider_analytics/src/aider_analytics/main.py`

```python
#!/usr/bin/env python
"""
Analytics tool for distinguishing between human and AI commit patterns.
"""

import os
import subprocess
import logging
import click
import matplotlib.pyplot as plt
from pathlib import Path
from typing import List, Tuple, Dict

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("aider_analytics")


def get_git_commits(repo_path: str) -> List[str]:
    """Get all commit messages from the Git repository."""
    try:
        # Change to the repository directory
        original_dir = os.getcwd()
        os.chdir(repo_path)
        
        # Run git log to get commit messages
        result = subprocess.run(
            ["git", "log", "--pretty=format:%s"],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Return to the original directory
        os.chdir(original_dir)
        
        # Split the output by lines and return
        return result.stdout.strip().split("\n") if result.stdout.strip() else []
    except subprocess.CalledProcessError as e:
        logger.error(f"Git command failed: {e}")
        return []
    except Exception as e:
        logger.error(f"Error accessing repository: {e}")
        return []


def classify_commits(commit_messages: List[str]) -> Tuple[List[str], List[str]]:
    """
    Classify commit messages as aider (AI) or human based ONLY on the presence of a colon.
    
    If a commit message contains a colon, it's classified as an aider commit.
    Otherwise, it's classified as a human commit.
    """
    aider_commits = []
    human_commits = []
    
    for message in commit_messages:
        if ":" in message:
            aider_commits.append(message)
        else:
            human_commits.append(message)
    
    return aider_commits, human_commits


def generate_analytics(repo_path: str, output_dir: str = None) -> Dict:
    """Generate analytics on commit patterns."""
    # Get commit messages
    commits = get_git_commits(repo_path)
    
    if not commits:
        logger.warning("No commits found in repository")
        return {"total": 0, "aider": 0, "human": 0, "ratio": 0}
    
    # Classify commits
    aider_commits, human_commits = classify_commits(commits)
    
    # Calculate statistics
    total_commits = len(commits)
    aider_count = len(aider_commits)
    human_count = len(human_commits)
    
    # Avoid division by zero
    aider_ratio = aider_count / total_commits if total_commits > 0 else 0
    
    # Create a dictionary with the results
    results = {
        "total": total_commits,
        "aider": aider_count,
        "human": human_count,
        "ratio": aider_ratio
    }
    
    # Generate and save visualization if output_dir is provided
    if output_dir:
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Create pie chart
        labels = ["AI Commits", "Human Commits"]
        sizes = [aider_count, human_count]
        colors = ["#4285F4", "#34A853"]
        
        plt.figure(figsize=(10, 7))
        plt.pie(sizes, labels=labels, colors=colors, autopct="%1.1f%%", startangle=90)
        plt.axis("equal")
        plt.title(f"Commit Distribution in {os.path.basename(repo_path)}")
        
        # Save the chart
        chart_path = output_path / "commit_distribution.png"
        plt.savefig(chart_path)
        logger.info(f"Chart saved to {chart_path}")
        
        # Close the plot to free memory
        plt.close()
    
    return results


@click.command()
@click.argument("repo_path", type=click.Path(exists=True), default=".")
@click.option("--output-dir", "-o", type=click.Path(), help="Directory to save analytics outputs")
def main(repo_path, output_dir):
    """Analyze Git commits to distinguish between AI and human contributions."""
    logger.info(f"Analyzing repository: {repo_path}")
    
    results = generate_analytics(repo_path, output_dir)
    
    # Print results
    print("\n===== Commit Analysis Results =====")
    print(f"Total commits: {results['total']}")
    print(f"AI commits: {results['aider']} ({results['ratio']*100:.1f}%)")
    print(f"Human commits: {results['human']} ({(1-results['ratio'])*100:.1f}%)")
    print("==================================\n")
    
    if output_dir:
        print(f"Charts have been saved to: {output_dir}")


if __name__ == "__main__":
    main()
```

### 4. Update Justfile References

Modify the justfile to update references to the original script:

```diff
# === Analysis ===
analytics:
    @echo "📊 Running commit analysis..."
-   @python aider_analytics.py
+   @aider-analytics .
```

### 5. Remove Original Script

```
rm aider_analytics.py
```

# Part II: Moving montaigne to UV Workspace

## Overview

This section outlines the steps to move the existing `montaigne` module from the current `src/montaigne/` location to a workspace package structure under `packages/montaigne/`.

## Changes Required

### 1. Create New Directory Structure

Create the destination directory structure:

```bash
mkdir -p packages/montaigne/src/montaigne
```

### 2. Move Python Module Files

Move the Python files from the current location to the workspace package:

```bash
# Move all Python files from src/montaigne to packages/montaigne/src/montaigne
cp -r src/montaigne/*.py packages/montaigne/src/montaigne/
```

### 3. Create Package Configuration File

Create a new `pyproject.toml` for the montaigne package:

#### `packages/montaigne/pyproject.toml`

```toml
[project]
name = "montaigne"
version = "0.1.0"
description = "CLI tool for TTS (XTTS) with text preprocessing (pauses, emphasis, tone tags) and evaluation (Whisper)."
authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
requires-python = ">=3.11,<3.12"
dependencies = [
    "click==8.1.8",
    "requests>=2.31.0",
    "TTS==0.22.0",
    "suno-bark @ git+https://github.com/suno-ai/bark.git",
    "openai-whisper==20240930",
    "rapidfuzz==3.13.0",
    "pydub>=0.25.0",
    "yt-dlp>=2023.0.0",
    "soundfile>=0.12.1",
    "matplotlib>=3.5.0",
    "sounddevice>=0.4.5",
    "numpy>=1.20.0",
    "piper-tts>=1.2.0",
    "transformers>=4.0.0",
    "accelerate>=0.20.0",
    "huggingface-hub>=0.20.0",
]

[project.optional-dependencies]
dev = [
    "ruff==0.11.7",
    "pytest==8.3.5",
    "build==1.2.2.post1",
]

[project.scripts]
montaigne = "montaigne.main:cli"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[tool.ruff]
line-length = 88
select = ["E", "F", "W", "I", "N", "C4", "UP", "ARG", "B"]
ignore = ["B008"]

[tool.ruff.format]
quote-style = "double"
```

### 4. Add Package __init__.py

Create a proper `__init__.py` file:

#### `packages/montaigne/src/montaigne/__init__.py`

```python
"""
CLI tool for TTS (XTTS) with text preprocessing (pauses, emphasis, tone tags) and evaluation (Whisper).
"""

__version__ = "0.1.0"
```

### 5. Update Root pyproject.toml

Update the root `pyproject.toml` to remove direct montaigne dependencies and ensure workspace configuration:

```diff
[project]
name = "montaigne-bff"
version = "0.1.0"
description = "Montaigne TTS Backend for Frontend Architecture"
authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
requires-python = ">=3.11,<3.12"
-dependencies = [
-    "click==8.1.8",
-    "requests>=2.31.0",
-    "TTS==0.22.0",
-    "suno-bark @ git+https://github.com/suno-ai/bark.git",
-    "openai-whisper==20240930",
-    # Other montaigne dependencies...
-]
+dependencies = []

[tool.uv.workspace]
members = ["packages/*"]

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"
```

### 6. Update Paths in Package Files (if necessary)

If there are any hardcoded imports or paths within the montaigne module files that reference the old structure, update them to reflect the new workspace structure.

### 7. Update Imports in Cicero Backend

If the Cicero backend imports from montaigne, update those imports:

#### `packages/cicero/pyproject.toml`

```diff
[tool.uv.sources]
+montaigne = { workspace = true }
```

### 8. Remove Old Directory Structure

After testing that everything works correctly, remove the old directory structure:

```bash
rm -rf src/montaigne
rm -rf src/montaigne.egg-info
```

## Testing Both Workspace Migrations

After implementing these changes, you should:

1. Enter the Nix development environment:
   ```
   just nix
   ```

2. Check that the workspace setup is correct:
   ```
   uv lock
   ```

3. Test the aider-analytics command:
   ```
   aider-analytics .
   ```

4. Test the montaigne command:
   ```
   montaigne --help
   ```

5. Test the justfile tasks:
   ```
   just analytics
   just xtts
   ```

## Implementation Notes

1. **Workspace Integration**: Both packages are now integrated into the workspace configuration with `members = ["packages/*"]` in the root pyproject.toml.

2. **Simplified Detection Logic**: In aider-analytics, the commit classification now uses the presence of a colon as the sole criterion for identifying AI-generated commits, as specified in the requirements.

3. **Script Conversion**: The aider_analytics script has been converted to a proper package with an entry point, making it available as a command (`aider-analytics`) after installation.

4. **Consistent Structure**: Both packages now follow the src-layout pattern, which is considered a best practice for Python packages.

5. **Dependency Management**: Each package declares its specific dependencies in its own `pyproject.toml` file, which allows for better dependency isolation while still sharing a common lockfile.

This approach gives you the benefits of a uv workspace:
- Common lockfile ensuring consistent dependencies
- Ability to manage dependencies separately for each package
- Simplified commands like `uv run --package <package-name>`
- Better organization of your codebase into logical components