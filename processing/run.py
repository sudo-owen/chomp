#!/usr/bin/env python3
"""
Meta script to orchestrate the full deploy flow.

Usage:
    python processing/deploy.py <RPC_URL>

Flow:
    1. Run createMonsAndMoves.py to validate data and update SetupMons.sol
    2. Prompt for keystore password
    3. Run forge scripts
    4. Run createAddressAndABIs.py with all collected addresses
"""

import argparse
import getpass
import os
import pty
import select
import subprocess
import sys
from pathlib import Path


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


def run_forge_script(script_name: str, rpc_url: str, password: str) -> tuple[bool, str]:
    """
    Run a forge script and return (success, output).
    Uses a pseudo-terminal to handle interactive prompts (password, size limit).
    """
    print(f"\n{'=' * 80}")
    print(f"Running forge script: {script_name}")
    print("=" * 80)

    cmd = [
        "forge", "script",
        f"script/{script_name}.s.sol",
        "--rpc-url", rpc_url,
        "--account", ACCOUNT_NAME,
        "--sender", SENDER_ADDRESS,
        "--broadcast",
        "--skip-simulation",
        "--legacy"
    ]

    # Create a pseudo-terminal so forge thinks it's running interactively
    master_fd, slave_fd = pty.openpty()

    process = subprocess.Popen(
        cmd,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        text=False,
        cwd=os.getcwd()
    )

    os.close(slave_fd)

    output_bytes = []
    password_sent = False
    buffer = ""

    try:
        while True:
            # Check if there's data to read
            ready, _, _ = select.select([master_fd], [], [], 0.1)

            if ready:
                try:
                    data = os.read(master_fd, 1024)
                    if not data:
                        break
                    output_bytes.append(data)
                    text = data.decode('utf-8', errors='replace')
                    print(text, end='', flush=True)
                    buffer += text

                    # Send password when prompted
                    if not password_sent and "Enter password" in buffer:
                        os.write(master_fd, (password + "\n").encode())
                        password_sent = True
                        buffer = ""

                    # Respond 'y' to contract size limit prompts
                    if "Do you wish to continue?" in buffer:
                        os.write(master_fd, b"y\n")
                        buffer = ""

                except OSError:
                    break

            # Check if process has exited
            if process.poll() is not None:
                # Read any remaining output
                while True:
                    ready, _, _ = select.select([master_fd], [], [], 0.1)
                    if not ready:
                        break
                    try:
                        data = os.read(master_fd, 1024)
                        if not data:
                            break
                        output_bytes.append(data)
                        text = data.decode('utf-8', errors='replace')
                        print(text, end='', flush=True)
                    except OSError:
                        break
                break

    finally:
        os.close(master_fd)

    stdout = b''.join(output_bytes).decode('utf-8', errors='replace')
    return process.returncode == 0, stdout


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


def deploy_all_scripts(rpc_url: str, password: str) -> list[str]:
    """
    Deploy all forge scripts in order, updating .env after each.
    Returns all collected env lines.
    """
    all_env_lines = []

    for i, script_name in enumerate(DEPLOY_SCRIPTS, start=1):
        print(f"\n{'=' * 80}")
        print(f"STEP {i + 1}: Deploying {script_name}")
        print("=" * 80)

        success, output = run_forge_script(script_name, rpc_url, password)
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

    # Step 2: Prompt for keystore password
    print(f"\n{'=' * 80}")
    print("STEP 2: Keystore Password")
    print("=" * 80)
    password = getpass.getpass(f"Enter password for keystore account '{ACCOUNT_NAME}': ")

    # Steps 3+: Deploy all forge scripts
    all_env_lines = deploy_all_scripts(args.rpc_url, password)

    # Final step: Run createAddressAndABIs.py
    final_step = len(DEPLOY_SCRIPTS) + 3
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

