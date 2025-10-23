#!/usr/bin/env python3
"""
Combined script to orchestrate mon and move data processing.

This script:
1. Runs moveCheck.py to validate move contracts against CSV data
2. If validation passes or user declines to make changes, runs monStatsToSol.py to update SetupMons.sol
3. Finally, runs combine.py to create mon_data.ts with the latest data
"""

import os
import sys
import subprocess
from pathlib import Path


def run_move_check() -> bool:
    """
    Run moveCheck.py and return whether changes should be made to Solidity files.

    Returns:
        True if changes should be made (user said 'y'), False otherwise
    """
    print("="*80)
    print("STEP 1: Running moveCheck.py to validate move contracts")
    print("="*80)
    print()

    # Import and run moveCheck
    sys.path.insert(0, str(Path(__file__).parent))

    try:
        from moveCheck import MoveValidator

        # Set up paths
        csv_path = "drool/moves.csv"
        src_path = "src/"

        # Validate paths exist
        if not os.path.exists(csv_path):
            print(f"Error: CSV file not found: {csv_path}")
            return False

        if not os.path.exists(src_path):
            print(f"Error: Source directory not found: {src_path}")
            return False

        # Run validation
        validator = MoveValidator(csv_path, src_path)
        validator.run_validation()

        # Check if there were errors
        moves_with_errors = sum(1 for result in validator.validation_results if result['errors'])

        if moves_with_errors > 0:
            # The validator already prompted the user and potentially made changes
            # Check if changes were actually made by looking at the response
            # Since we can't directly access the user's response, we'll return False
            # to indicate that we should NOT proceed (user either declined or changes were made)
            return False
        else:
            # No errors, proceed to next step
            print("\n✅ All move validations passed!")
            return True

    except Exception as e:
        print(f"Error running moveCheck.py: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_mon_stats_to_sol() -> bool:
    """
    Run monStatsToSol.py to update SetupMons.sol.

    Returns:
        True if successful, False otherwise
    """
    print("\n")
    print("="*80)
    print("STEP 2: Running monStatsToSol.py to update SetupMons.sol")
    print("="*80)
    print()

    try:
        # Run monStatsToSol.py as a subprocess
        result = subprocess.run(
            [sys.executable, "processing/monStatsToSol.py"],
            cwd=os.getcwd(),
            capture_output=True,
            text=True
        )

        # Print output
        print(result.stdout)
        if result.stderr:
            print("Errors:", result.stderr)

        if result.returncode != 0:
            print(f"❌ monStatsToSol.py failed with return code {result.returncode}")
            return False

        print("✅ SetupMons.sol updated successfully!")
        return True

    except Exception as e:
        print(f"Error running monStatsToSol.py: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_combine() -> bool:
    """
    Run combine.py to create mon_data.ts.

    Returns:
        True if successful, False otherwise
    """
    print("\n")
    print("="*80)
    print("STEP 3: Running combine.py to create mon_data.ts")
    print("="*80)
    print()

    try:
        # Run combine.py as a subprocess
        result = subprocess.run(
            [sys.executable, "drool/combine.py"],
            cwd=os.getcwd(),
            capture_output=True,
            text=True
        )

        # Print output
        print(result.stdout)
        if result.stderr:
            print("Errors:", result.stderr)

        if result.returncode != 0:
            print(f"❌ combine.py failed with return code {result.returncode}")
            return False

        print("✅ mon.ts created successfully!")
        return True

    except Exception as e:
        print(f"Error running combine.py: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Main orchestration function"""

    # Step 1: Run moveCheck
    should_proceed = run_move_check()

    if not should_proceed:
        print("\n⚠️  Stopping: Move validation found errors or changes were made.")
        print("Please review the changes and run this script again.")
        sys.exit(1)

    # Step 2: Run monStatsToSol
    if not run_mon_stats_to_sol():
        print("\n❌ Failed to update SetupMons.sol")
        sys.exit(1)

    # Step 3: Run combine
    if not run_combine():
        print("\n❌ Failed to create mon.ts")
        sys.exit(1)

    # Success!
    print("\n")
    print("="*80)
    print("Success")
    print()


if __name__ == "__main__":
    main()
