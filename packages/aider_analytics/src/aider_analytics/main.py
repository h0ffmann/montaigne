#!/usr/bin/env python
"""
Analytics tool for distinguishing between human and AI commit patterns.
"""

import logging
import os
import subprocess
from pathlib import Path

import click
import matplotlib.pyplot as plt

# Set up logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("aider_analytics")


def get_git_commits(repo_path: str) -> list[str]:
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
            check=True,
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


def classify_commits(commit_messages: list[str]) -> tuple[list[str], list[str]]:
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


def generate_analytics(repo_path: str, output_dir: str = None) -> dict:
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
        "ratio": aider_ratio,
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
@click.option(
    "--output-dir", "-o", type=click.Path(), help="Directory to save analytics outputs"
)
def main(repo_path, output_dir):
    """Analyze Git commits to distinguish between AI and human contributions."""
    logger.info(f"Analyzing repository: {repo_path}")

    results = generate_analytics(repo_path, output_dir)

    # Print results
    print("\n===== Commit Analysis Results =====")
    print(f"Total commits: {results['total']}")
    print(f"AI commits: {results['aider']} ({results['ratio'] * 100:.1f}%)")
    print(f"Human commits: {results['human']} ({(1 - results['ratio']) * 100:.1f}%)")
    print("==================================\n")

    if output_dir:
        print(f"Charts have been saved to: {output_dir}")


if __name__ == "__main__":
    main()
