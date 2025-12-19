#!/usr/bin/env python3
"""
Meta script to orchestrate the full deploy flow.

Usage:
    python processing/run.py <RPC_URL>

Flow:
    1. Run createMonsAndMoves.py to validate data and update SetupMons.sol
    2. Run forge scripts (user handles interactive prompts)
    3. Run createAddressAndABIs.py with all collected addresses
"""

import argparse
import io
import os
import subprocess
import sys
from pathlib import Path
import pexpect


SENDER_ADDRESS = "0x4206957609f2936D166aF8E5d0870a11496302AD"
ACCOUNT_NAME = "defaultKey"


def run_create_mons_and_moves() -> bool:
    """
    Run createMonsAndMoves.py and pipe output to console.
    Returns True if user wants to proceed, False otherwise.
    """
    print("=" * 80)
    print("STEP 1: Running createMonsAndMoves.py")
    print("=" * 80)
    print()

    result = subprocess.run(
        [sys.executable, "processing/createMonsAndMoves.py"],
        cwd=os.getcwd()
    )

    if result.returncode != 0:
        return False

    print()
    response = input("Proceed with deployment? (y/n): ").strip().lower()
    return response == 'y'


def run_forge_script(script_name: str, rpc_url: str) -> tuple[bool, str]:
    """
    Run a forge script and return (success, output).
    Uses pexpect to hand control to user for interactive prompts (password, confirmations).
    """
    print(f"\n{'=' * 80}")
    print(f"Running forge script: {script_name}")
    print("=" * 80)

    cmd = f"forge script script/{script_name}.s.sol --rpc-url {rpc_url} --account {ACCOUNT_NAME} --sender {SENDER_ADDRESS} --broadcast --skip-simulation --legacy"

    # Use BytesIO to capture output (interact() logs bytes regardless of encoding setting)
    log_buffer = io.BytesIO()

    child = pexpect.spawn(cmd, timeout=300)
    child.logfile_read = log_buffer  # Capture all output that's read

    # Hand control to user for interactive prompts
    child.interact()
    child.wait()

    output = log_buffer.getvalue().decode('utf-8', errors='replace')
    return child.exitstatus == 0, output


def parse_deploy_output(output: str) -> list[str]:
    """Parse forge output and return KEY=VALUE lines."""
    # Import the parsing function from deployToEnv
    sys.path.insert(0, str(Path(__file__).parent))
    from deployToEnv import parse_content_to_env_lines

    return parse_content_to_env_lines(output)


def update_env_file(env_lines: list[str], env_path: str = ".env"):
    """Update .env file with new values, preserving existing ones."""
    existing = {}

    # Read existing .env if it exists
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and '=' in line and not line.startswith('#'):
                    key, value = line.split('=', 1)
                    existing[key] = value

    # Update with new values
    for line in env_lines:
        if '=' in line:
            key, value = line.split('=', 1)
            existing[key] = value

    # Write back
    with open(env_path, 'w') as f:
        for key, value in existing.items():
            f.write(f"{key}={value}\n")

    print(f"✅ Updated {env_path} with {len(env_lines)} new values")


def run_create_address_and_abis(all_env_lines: list[str]):
    """Run createAddressAndABIs.py with collected addresses via stdin."""
    print(f"\n{'=' * 80}")
    print("Running createAddressAndABIs.py")
    print("=" * 80)

    content = "\n".join(all_env_lines)

    result = subprocess.run(
        [sys.executable, "processing/createAddressAndABIs.py", "--stdin"],
        input=content,
        text=True,
        cwd=os.getcwd()
    )

    return result.returncode == 0


# Order of forge scripts to deploy
DEPLOY_SCRIPTS = [
    "EngineAndPeriphery",
    "SetupMons",
    "SetupCPU",
]


def deploy_all_scripts(rpc_url: str) -> list[str]:
    """
    Deploy all forge scripts in order, updating .env after each.
    Returns all collected env lines.
    """
    all_env_lines = []

    for i, script_name in enumerate(DEPLOY_SCRIPTS, start=1):
        print(f"\n{'=' * 80}")
        print(f"STEP {i + 1}: Deploying {script_name}")
        print("=" * 80)

        success, output = run_forge_script(script_name, rpc_url)
        if not success:
            print(f"\n❌ {script_name} deployment failed")
            sys.exit(1)

        env_lines = parse_deploy_output(output)
        all_env_lines.extend(env_lines)
        update_env_file(env_lines)

    return all_env_lines


def main():
    parser = argparse.ArgumentParser(
        description='Orchestrate the full deploy flow'
    )
    parser.add_argument(
        'rpc_url',
        help='RPC URL for the target chain'
    )
    args = parser.parse_args()

    # Step 1: Run createMonsAndMoves.py
    if not run_create_mons_and_moves():
        print("\n❌ Deployment cancelled or createMonsAndMoves.py failed")
        sys.exit(1)

    # Step 2+: Deploy all forge scripts
    all_env_lines = deploy_all_scripts(args.rpc_url)

    # Final step: Run createAddressAndABIs.py
    final_step = len(DEPLOY_SCRIPTS) + 2
    print(f"\n{'=' * 80}")
    print(f"STEP {final_step}: Updating TypeScript addresses and ABIs")
    print("=" * 80)

    if not run_create_address_and_abis(all_env_lines):
        print("\n❌ createAddressAndABIs.py failed")
        sys.exit(1)

    # Done!
    print(f"\n{'=' * 80}")
    print("✅ DEPLOYMENT COMPLETE!")
    print("=" * 80)
    print(f"\nTotal contracts deployed: {len(all_env_lines)}")


if __name__ == "__main__":
    main()

