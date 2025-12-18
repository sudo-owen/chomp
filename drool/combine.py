#!/usr/bin/env python3
"""
Script to combine mons.csv, moves.csv, and abilities.csv into a TypeScript const data structure.
"""

import csv
import json
import re
from pathlib import Path
from typing import Dict, List, Any


def move_name_to_address_key(move_name: str) -> str:
    """Convert move name to UPPER_SNAKE_CASE for address key."""
    # Replace spaces and special characters with underscores
    key = re.sub(r"[^a-zA-Z0-9]", "_", move_name)
    # Convert to uppercase
    key = key.upper()
    # Remove multiple consecutive underscores
    key = re.sub(r"_+", "_", key)
    # Remove leading/trailing underscores
    key = key.strip("_")
    return key


def read_mons_data(file_path: str) -> Dict[int, Dict[str, Any]]:
    """Read mons.csv and return a dictionary keyed by mon ID."""
    mons_data = {}

    with open(file_path, "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        for row in reader:
            mon_id = int(row["Id"])
            mon_name_lower = row["Name"].lower()
            mons_data[mon_id] = {
                "id": mon_id,
                "name": row["Name"],
                "flavor": row.get("Flavor", ""),
                "frontImage": f"/assets/mons/all/{mon_name_lower}_front.gif",
                "backImage": f"/assets/mons/all/{mon_name_lower}_back.gif",
                "mini": f"/assets/mons/all/{mon_name_lower}_mini.gif",
                "frontSwitchInImage": f"/assets/mons/all/{mon_name_lower}_front_switch_in.gif",
                "frontSwitchOutImage": f"/assets/mons/all/{mon_name_lower}_front_switch_out.gif",
                "backSwitchInImage": f"/assets/mons/all/{mon_name_lower}_back_switch_in.gif",
                "backSwitchOutImage": f"/assets/mons/all/{mon_name_lower}_back_switch_out.gif",
                "stats": {
                    "hp": int(row["HP"]),
                    "attack": int(row["Attack"]),
                    "defense": int(row["Defense"]),
                    "specialAttack": int(row["SpecialAttack"]),
                    "specialDefense": int(row["SpecialDefense"]),
                    "speed": int(row["Speed"]),
                    "bst": int(row["BST"]),
                },
                "type1": row["Type1"],
                "type2": row["Type2"] if row["Type2"] != "NA" else None,
                "moves": [],
                "ability": {"address": "", "name": "", "effect": ""},
            }

    return mons_data


def read_moves_data(file_path: str) -> Dict[str, List[Dict[str, Any]]]:
    """Read moves.csv and return a dictionary keyed by mon name."""
    moves_by_mon = {}

    with open(file_path, "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        for row in reader:
            mon_name = row["Mon"]
            if mon_name not in moves_by_mon:
                moves_by_mon[mon_name] = []

            address_key = move_name_to_address_key(row["Name"])
            move_data = {
                "address": f"Address.{address_key}",
                "name": row["Name"],
                "power": int(row["Power"]) if row["Power"].isdigit() else '?',
                "stamina": int(row["Stamina"]) if row["Stamina"].isdigit() else '?',
                "accuracy": int(row["Accuracy"]) if row["Accuracy"].isdigit() else '?',
                "priority": int(row["Priority"]) if row["Priority"].isdigit() else '?',
                "type": row["Type"],
                "class": row["Class"],
                "description": row["DevDescription"], # Change to UserDescription later
                "extraDataNeeded": row["ExtraData"] == "Yes",
            }
            moves_by_mon[mon_name].append(move_data)

    return moves_by_mon


def read_abilities_data(file_path: str) -> Dict[str, Dict[str, str]]:
    """Read abilities.csv and return a dictionary keyed by mon name."""
    abilities_by_mon = {}

    with open(file_path, "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        for row in reader:
            mon_name = row["Mon"]
            address_key = move_name_to_address_key(row["Name"])
            abilities_by_mon[mon_name] = {
                "address": f"Address.{address_key}",
                "name": row["Name"],
                "effect": row["Effect"],
            }

    return abilities_by_mon


def combine_data(
    mons_data: Dict[int, Dict[str, Any]],
    moves_by_mon: Dict[str, List[Dict[str, Any]]],
    abilities_by_mon: Dict[str, Dict[str, str]],
) -> Dict[int, Dict[str, Any]]:
    """Combine all data sources into a single structure."""

    for mon_id, mon_data in mons_data.items():
        mon_name = mon_data["name"]

        # Add moves for this mon
        if mon_name in moves_by_mon:
            mon_data["moves"] = moves_by_mon[mon_name]

        # Add ability for this mon
        if mon_name in abilities_by_mon:
            mon_data["ability"] = abilities_by_mon[mon_name]

    return mons_data


def generate_typescript_const(data: Dict[int, Dict[str, Any]], output_file: str):
    """Generate TypeScript const declaration and write to file."""

    # Convert to JSON string with proper formatting
    json_str = json.dumps(data, indent=2, ensure_ascii=False)

    # Replace string keys with integer keys (JSON converts int keys to strings)
    json_str = re.sub(r'"(\d+)":', r"\1:", json_str)

    # Replace address string references with actual Address object references
    json_str = re.sub(r'"Address\.([A-Z0-9_]+)"', r"Address.\1", json_str)

    # Replace type string values with Type enum references
    type_values = [
        "Yin",
        "Yang",
        "Earth",
        "Liquid",
        "Fire",
        "Metal",
        "Ice",
        "Nature",
        "Lightning",
        "Mythic",
        "Air",
        "Math",
        "Cyber",
        "Wild",
        "Cosmic",
    ]
    for type_value in type_values:
        json_str = re.sub(f'"{type_value}"', f"Type.{type_value}", json_str)

    # Replace class string values with MoveClass enum references
    class_values = ["Physical", "Special", "Other", "Self"]
    for class_value in class_values:
        json_str = re.sub(f'"{class_value}"', f"MoveClass.{class_value}", json_str)

    # Create TypeScript const declaration
    typescript_content = f"""// Auto-generated type file
import {{ Address }} from './address';
import {{ LowercaseHex, Type }} from '../types/structs';

export enum MoveClass {{
  Physical = 'Physical',
  Special = 'Special',
  Other = 'Other',
  Self = 'Self',
}};

export const MonMetadata = {json_str} as const;

export type Move = {{
  readonly address: LowercaseHex;
  readonly name: string;
  readonly power: number | '?';
  readonly stamina: number | '?';
  readonly accuracy: number | '?';
  readonly priority: number | '?';
  readonly type: Type;
  readonly class: MoveClass;
  readonly description: string;
  readonly extraDataNeeded: boolean;
}};

export type Mon = {{
  readonly id: number;
  readonly name: string;
  readonly flavor: string;
  readonly frontImage: string;
  readonly backImage: string;
  readonly mini: string;
    readonly frontSwitchInImage: string;
  readonly frontSwitchOutImage: string;
  readonly backSwitchInImage: string;
  readonly backSwitchOutImage: string;
  readonly stats: {{
    readonly hp: number;
    readonly attack: number;
    readonly defense: number;
    readonly specialAttack: number;
    readonly specialDefense: number;
    readonly speed: number;
    readonly bst: number;
  }};
  readonly type1: Type;
  readonly type2: Type | null;
  readonly moves: readonly [Move, Move, Move, Move, ...Array<Move>];
  readonly ability: {{
    readonly address: LowercaseHex;
    readonly name: string;
    readonly effect: string;
  }};
}};

export type MonDatabase = Record<number, Mon>;
"""

    with open(output_file, "w", encoding="utf-8") as file:
        file.write(typescript_content)


def main():
    """Main function to orchestrate the data combination."""
    base_path = Path(__file__).parent

    # File paths
    mons_file = base_path / "mons.csv"
    moves_file = base_path / "moves.csv"
    abilities_file = base_path / "abilities.csv"

    # Try to output to munch repo first, fall back to local if it doesn't exist
    # base_path is /game/chomp/drool, so we need to go up 2 levels to /game
    game_dir = base_path.parent.parent
    munch_output_file = game_dir / "munch" / "src" / "app" / "data" / "mon.ts"
    fallback_output_file = base_path / "mon_data.ts"

    if munch_output_file.parent.exists():
        output_file = munch_output_file
        print(f"Output target: {output_file} (munch repository)")
    else:
        output_file = fallback_output_file
        print(f"Output target: {output_file} (fallback - munch repository not found)")

    # Check if all files exist
    for file_path in [mons_file, moves_file, abilities_file]:
        if not file_path.exists():
            print(f"Error: {file_path} not found!")
            return

    print("Reading CSV files...")

    # Read data from CSV files
    mons_data = read_mons_data(str(mons_file))
    moves_by_mon = read_moves_data(str(moves_file))
    abilities_by_mon = read_abilities_data(str(abilities_file))

    print(f"Loaded {len(mons_data)} mons")
    print(f"Loaded moves for {len(moves_by_mon)} mons")
    print(f"Loaded abilities for {len(abilities_by_mon)} mons")

    # Combine all data
    combined_data = combine_data(mons_data, moves_by_mon, abilities_by_mon)

    # Generate TypeScript file
    generate_typescript_const(combined_data, str(output_file))

    print(f"✅ Generated TypeScript const in {output_file}")
    print("Done!")


if __name__ == "__main__":
    main()
