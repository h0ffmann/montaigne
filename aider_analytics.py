import subprocess
import re
import collections
import argparse
import matplotlib.pyplot as plt
import math
from pathlib import Path

# --- Configuration ---
COMMIT_TYPES = {
    "feat": "Features",
    "fix": "Bug Fixes",
    "refactor": "Code Refactoring",
    "chore": "Chores/Maintenance",
    "docs": "Documentation",
    "style": "Style Changes",
    "test": "Tests",
    "perf": "Performance Improvements",
    "ci": "CI/CD",
    "build": "Build System",
    # Add other types if needed
}

# Simple list of common English stop words + Git/code terms
STOP_WORDS = set([
    "a", "an", "the", "and", "or", "in", "on", "at", "to", "for", "with",
    "of", "by", "as", "is", "it", "was", "were", "be", "this", "that",
    "fix", "feat", "refactor", "chore", "docs", "test", "style", "perf", "ci",
    "build", "add", "update", "remove", "change", "use", "from", "improve",
    "make", "ensure", "via", "allow", "support", "handle", "git", "commit",
    "file", "files", "code", "script", "issue", "merged", "pull", "request",
    "branch", "master", "main", "into", "github", "gitlab", "message",
    "aider", "log", "lint", "format", "dependencies", "package", "version",
    "config", "release", "bump", "set", "get", "run", "when", "will",
    "not", "no", "has", "had", "but", "if", "so", "up", "out", "all",
    "now", "just", "only", "also", "new", "old", "fix:", "feat:", "refactor:",
    "chore:", "docs:", "test:", "style:", "perf:", "ci:", "build:", "and", "to"
])

MIN_TERM_LENGTH = 3
TOP_N_DEFAULT = 15 # Default number for top terms/files plots

# --- Helper Functions ---

def run_git_command(command):
    """Runs a Git command and returns its output."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True, encoding='utf-8')
        return result.stdout
    except FileNotFoundError:
        print("❌ Error: 'git' command not found. Is Git installed and in your PATH?")
        exit(1)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running Git command: {' '.join(command)}")
        print(f"Stderr: {e.stderr}")
        exit(1)

def get_commits(n_commits=None):
    """Fetches commit data using git log."""
    # Format: Hash\nAuthorName\nAuthorEmail\nDateYYYY-MM-DD\nSubject\nBody\n--numstat-separator--\nnumstat output...
    # Using a unique separator simplifies parsing the body vs numstat
    git_format = "%H%n%an%n%ae%n%cs%n%s%n%b%n--numstat-separator--"
    command = ["git", "log", f"--pretty=format:{git_format}", "--numstat"]
    if n_commits:
        command.append(f"-n {n_commits}")

    print(f"🔍 Fetching Git log data ({'last ' + str(n_commits) if n_commits else 'all'} commits)...")
    raw_log = run_git_command(command)
    print("✅ Git log data fetched.")
    return raw_log

def parse_log_data(log_output):
    """Parses the formatted git log output."""
    commits = []
    # Split commits using the full hash which starts each entry
    raw_commits = re.split(r'\n([a-f0-9]{40})\n', '\n' + log_output.strip())
    # The split results in ['', hash1, commit_data1, hash2, commit_data2, ...]

    if not raw_commits or len(raw_commits) < 3:
        if log_output.strip(): # Check if there was output but split failed
             print("⚠️ Warning: Could not split commits based on hash. Log format might be unexpected.")
             print("Raw log sample:", log_output[:500])
        return []

    commit_iter = iter(raw_commits[1:]) # Skip initial empty string
    parsed_count = 0
    skipped_merges = 0

    for commit_hash in commit_iter:
        try:
            commit_data_raw = next(commit_iter).strip()
            parts = commit_data_raw.split('\n', maxsplit=5) # Split up to body

            if len(parts) < 6:
                print(f"⚠️ Warning: Skipping malformed commit data for hash starting {commit_hash[:7]}...")
                print(f"Data: {commit_data_raw[:200]}")
                continue # Skip this iteration

            author_name, author_email, date_str, subject, body_and_numstat = parts[1:] # Skip first (empty string before first newline)

             # Check for merge commits (often less informative for type analysis)
            if subject.lower().startswith("merge "):
                skipped_merges +=1
                continue # Skip merge commits by default

            body_and_numstat_parts = body_and_numstat.split("\n--numstat-separator--\n", maxsplit=1)
            body = body_and_numstat_parts[0].strip()
            numstat_raw = body_and_numstat_parts[1].strip() if len(body_and_numstat_parts) > 1 else ""

            files_changed = []
            if numstat_raw:
                for line in numstat_raw.split('\n'):
                    if not line.strip(): continue
                    try:
                        # Numstat format: <added>\t<deleted>\t<filepath>
                        added, deleted, filepath = line.split('\t', maxsplit=2)
                        # Ignore binary files which have '-' for added/deleted
                        if added != '-':
                            files_changed.append(filepath.strip())
                    except ValueError:
                         print(f"⚠️ Warning: Could not parse numstat line: '{line}' for commit {commit_hash[:7]}")


            commits.append({
                "hash": commit_hash,
                "author": author_name,
                "email": author_email,
                "date": date_str,
                "subject": subject.strip(),
                "body": body,
                "files": files_changed
            })
            parsed_count += 1
        except StopIteration:
            break # Should not happen if split is correct
        except Exception as e:
            print(f"🚨 Error parsing commit hash {commit_hash[:7]}: {e}")
            print(f"Data block causing error:\n{commit_data_raw[:500]}...") # Log problematic data

    if skipped_merges > 0:
         print(f"ℹ️ Skipped {skipped_merges} merge commits.")
    print(f"✅ Parsed {len(commits)} non-merge commits.")
    return commits


def analyze_commits(commits):
    """Performs the commit analysis."""
    if not commits:
        return {
            "commit_counts": collections.Counter(),
            "aider_commits": 0,
            "term_counts": collections.Counter(),
            "file_counts": collections.Counter(),
            "total_analyzed": 0
        }

    commit_counts = collections.Counter()
    aider_commits = 0
    term_counts = collections.Counter()
    file_counts = collections.Counter()
    
    # Pattern to detect aider in author name
    aider_author_pattern = re.compile(r'\(aider\)', re.IGNORECASE)
    
    # Patterns to identify conventional commit messages typically used by aider
    # Make this much more aggressive - assume ALL conventional commits are from Aider
    conventional_commit_pattern = re.compile(r'^(feat|fix|refactor|chore|docs|style|test|perf|ci|build)(\(.*?\))?:', re.IGNORECASE)
    
    # Additional patterns that might indicate aider commits
    aider_indicators = [
        re.compile(r'generated by', re.IGNORECASE),
        re.compile(r'automated', re.IGNORECASE),
        re.compile(r'ai-assisted', re.IGNORECASE),
        re.compile(r'with the help of', re.IGNORECASE),
        re.compile(r'improve', re.IGNORECASE),
        re.compile(r'update', re.IGNORECASE),
        re.compile(r'add', re.IGNORECASE),
        re.compile(r'implement', re.IGNORECASE),
        re.compile(r'create', re.IGNORECASE),
        re.compile(r'enhance', re.IGNORECASE),
        re.compile(r'optimize', re.IGNORECASE),
        re.compile(r'simplify', re.IGNORECASE),
        re.compile(r'correct', re.IGNORECASE)
    ]

    print(f"📊 Analyzing {len(commits)} commits...")

    for commit in commits:
        # 1. Commit Type Analysis
        subject_lower = commit['subject'].lower()
        commit_type_found = False
        for prefix, desc in COMMIT_TYPES.items():
            if subject_lower.startswith(prefix + ":") or subject_lower.startswith(prefix + "("):
                commit_counts[desc] += 1
                commit_type_found = True
                break
        if not commit_type_found:
            commit_counts["Other"] += 1

        # 2. Aider Commit Analysis - Improved logic with more aggressive detection
        is_aider_commit = False
        
        # Check for aider in author name
        if aider_author_pattern.search(commit['author']):
            is_aider_commit = True
        
        # Check for conventional commit format (feat:, fix:, etc.) - This is the main indicator
        elif conventional_commit_pattern.search(commit['subject']):
            is_aider_commit = True
            
        # Check for other aider indicators in commit message
        else:
            full_message = (commit['subject'] + ' ' + commit['body']).lower()
            for pattern in aider_indicators:
                if pattern.search(full_message):
                    is_aider_commit = True
                    break
                    
        # Additional heuristic: If commit message is very structured or follows patterns
        # typical of AI-generated content, mark as Aider commit
        if not is_aider_commit and len(commit['subject']) > 10:
            # Check for structured commit messages with colons or specific formatting
            if ':' in commit['subject'] or commit['subject'].startswith('feat') or commit['subject'].startswith('fix'):
                is_aider_commit = True
        
        if is_aider_commit:
            aider_commits += 1

        # 3. Term Frequency Analysis
        full_text = (commit['subject'] + ' ' + commit['body']).lower()
        # Basic tokenization, filter stop words and short words
        words = re.findall(r'\b\w+\b', full_text) # Find word boundaries
        for word in words:
            if word not in STOP_WORDS and len(word) >= MIN_TERM_LENGTH:
                term_counts[word] += 1

        # 4. File Change Frequency Analysis
        for file_path in commit['files']:
            file_counts[file_path] += 1

    print("✅ Analysis complete.")
    return {
        "commit_counts": commit_counts,
        "aider_commits": aider_commits,
        "term_counts": term_counts,
        "file_counts": file_counts,
        "total_analyzed": len(commits)
    }

def generate_report(analysis_data, total_commits_fetched):
    """Generates a formatted report string."""
    report_lines = ["="*60, " Git Commit Analysis Report", "="*60, ""]
    total_analyzed = analysis_data['total_analyzed']

    if total_analyzed == 0:
        report_lines.append("No non-merge commits found or parsed to analyze.")
        report_lines.append("="*60)
        return "\n".join(report_lines)

    report_lines.append(f"Total Commits Fetched: {total_commits_fetched}")
    report_lines.append(f"Total Non-Merge Commits Analyzed: {total_analyzed}\n")

    # Commit Type Report
    report_lines.append("-" * 20 + " Commit Types " + "-" * 20)
    commit_counts = analysis_data['commit_counts']
    sorted_types = sorted(commit_counts.items(), key=lambda item: item[1], reverse=True)
    for type_name, count in sorted_types:
        percentage = (count / total_analyzed) * 100
        report_lines.append(f"- {type_name:<20}: {count:>5} ({percentage:.1f}%)")
    report_lines.append("")

    # Aider Commit Report
    report_lines.append("-" * 20 + " Aider Commits " + "-" * 20)
    aider_commits = analysis_data['aider_commits']
    aider_percentage = (aider_commits / total_analyzed) * 100 if total_analyzed > 0 else 0
    report_lines.append(f"- Commits likely by Aider: {aider_commits:>5} ({aider_percentage:.1f}%)")
    report_lines.append(f"- Commits likely by Human: {total_analyzed - aider_commits:>5} ({100 - aider_percentage:.1f}%)")
    report_lines.append("")

    # Top Terms Report
    report_lines.append("-" * 20 + f" Top {TOP_N_DEFAULT} Terms (excluding stop words) " + "-" * 10)
    term_counts = analysis_data['term_counts']
    if term_counts:
        for term, count in term_counts.most_common(TOP_N_DEFAULT):
            report_lines.append(f"- {term:<25}: {count:>5}")
    else:
        report_lines.append("No significant terms found.")
    report_lines.append("")

    # Top Files Report
    report_lines.append("-" * 20 + f" Top {TOP_N_DEFAULT} Modified Files " + "-" * 14)
    file_counts = analysis_data['file_counts']
    if file_counts:
        for file_path, count in file_counts.most_common(TOP_N_DEFAULT):
            report_lines.append(f"- {file_path:<50}: {count:>5}")
    else:
        report_lines.append("No file modification data found.")
    report_lines.append("")

    report_lines.append("="*60)
    return "\n".join(report_lines)

# --- Plotting Functions ---

def plot_commit_types(commit_counts, total_analyzed, filename="commit_types.png"):
    """Generates and saves a pie chart for commit types."""
    if not commit_counts or total_analyzed == 0:
        print("ℹ️ Skipping commit type plot: No data.")
        return

    labels = []
    sizes = []
    # Group small percentages into 'Other' for clarity if necessary
    threshold = 2.0 # Group slices smaller than 2%
    other_size = 0
    other_count = 0

    sorted_types = sorted(commit_counts.items(), key=lambda item: item[1], reverse=True)

    for type_name, count in sorted_types:
         percentage = (count / total_analyzed) * 100
         if percentage < threshold:
             other_size += count
             other_count += 1
         else:
            labels.append(f"{type_name}\n({count}, {percentage:.1f}%)")
            sizes.append(count)

    if other_count > 0:
        other_percentage = (other_size / total_analyzed) * 100
        labels.append(f"Other ({other_count} types)\n({other_size}, {other_percentage:.1f}%)")
        sizes.append(other_size)

    if not sizes: # Only happened if all slices were below threshold
         print("ℹ️ Skipping commit type plot: All categories too small.")
         return

    plt.figure(figsize=(10, 8))
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=140, pctdistance=0.85)
    plt.title(f'Commit Type Distribution (Analyzed {total_analyzed} commits)')
    plt.axis('equal') # Equal aspect ratio ensures that pie is drawn as a circle.
    plt.tight_layout()
    plt.savefig(filename)
    plt.close()
    print(f"💾 Commit type plot saved to: {filename}")

def plot_top_items(counts, title, filename, top_n=TOP_N_DEFAULT, item_label="Items"):
    """Generates and saves a bar chart for top N items (terms or files)."""
    if not counts:
        print(f"ℹ️ Skipping {item_label} plot: No data.")
        return

    top_items = counts.most_common(top_n)
    if not top_items:
         print(f"ℹ️ Skipping {item_label} plot: No items after filtering.")
         return

    items = [item[0] for item in top_items]
    values = [item[1] for item in top_items]

    plt.figure(figsize=(12, max(6, 0.4 * len(items)))) # Adjust height based on number of items
    bars = plt.barh(range(len(items)), values, align='center', color='skyblue')
    plt.yticks(range(len(items)), items)
    plt.xlabel('Frequency / Count')
    plt.title(title)
    plt.gca().invert_yaxis()  # Display the highest count at the top

    # Add value labels on the bars
    for bar in bars:
        plt.text(bar.get_width() + 0.1, bar.get_y() + bar.get_height()/2,
                 f'{bar.get_width()}',
                 va='center', ha='left', fontsize=9)

    plt.tight_layout()
    plt.savefig(filename)
    plt.close()
    print(f"💾 {item_label} plot saved to: {filename}")


# --- Main Execution ---

def main():
    parser = argparse.ArgumentParser(description="Analyze Git commit history for patterns.")
    parser.add_argument(
        "-n", "--n-commits",
        type=int,
        help="Number of latest commits to analyze. Analyzes all if not specified."
    )
    parser.add_argument(
        "--skip-plots",
        action="store_true",
        help="Skip generating plot images."
    )
    args = parser.parse_args()

    raw_log = get_commits(args.n_commits)
    parsed_commits = parse_log_data(raw_log)

    # Calculate total fetched before filtering (for reporting context)
    # Approximation: count commit hashes in raw log
    total_commits_fetched = len(re.findall(r'^[a-f0-9]{40}$', raw_log, re.MULTILINE))
    if args.n_commits and total_commits_fetched > args.n_commits:
        total_commits_fetched = args.n_commits # Cap at requested number if specified


    analysis_results = analyze_commits(parsed_commits)

    report = generate_report(analysis_results, total_commits_fetched)
    print(report)

    # Generate plots if not skipped
    if not args.skip_plots:
         plot_dir = Path("./analysis_plots")
         plot_dir.mkdir(exist_ok=True)
         print(f"\n💾 Generating plots in '{plot_dir}'...")
         plot_commit_types(analysis_results['commit_counts'], analysis_results['total_analyzed'], filename=plot_dir / "commit_types.png")
         plot_top_items(analysis_results['term_counts'], f"Top {TOP_N_DEFAULT} Terms in Commit Messages", filename=plot_dir / "top_terms.png", item_label="Terms")
         plot_top_items(analysis_results['file_counts'], f"Top {TOP_N_DEFAULT} Modified Files", filename=plot_dir / "top_files.png", item_label="Files")


if __name__ == "__main__":
    main()
