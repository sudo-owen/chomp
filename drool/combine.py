#!/usr/bin/env python3
"""
Script to combine mons.csv, moves.csv, and abilities.csv into a TypeScript const data structure.
"""

import csv
import json
import re
from pathlib import Path
from typing import Dict, List, Any


def to_address_key(name: str) -> str:
    """Convert name to UPPER_SNAKE_CASE for address key."""
    return re.sub(r"_+", "_", re.sub(r"[^a-zA-Z0-9]", "_", name)).strip("_").upper()


def read_csv(file_path: str) -> List[Dict[str, str]]:
    """Read a CSV file and return list of row dicts."""
    with open(file_path, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_json(file_path: str) -> Dict[str, Any]:
    """Read a JSON file and return the data."""
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_sprites(mon_name_lower: str, spritesheet_data: Dict[str, Any]) -> Dict[str, Any]:
    """Build sprite configurations for a mon."""
    sprites = {}
    
    # Define sprite variants: (side, output_key, data_key, spritesheet, loops)
    SPRITE_VARIANTS = [
        ("front", "frontIdle", None, "mon_spritesheet.png", True),
        ("front", "frontSwitchIn", "switchIn", "mon_switch.png", False),
        ("front", "frontSwitchOut", "switchOut", "mon_switch.png", False),
        ("back", "backIdle", None, "mon_spritesheet.png", True),
        ("back", "backSwitchIn", "switchIn", "mon_switch.png", False),
        ("back", "backSwitchOut", "switchOut", "mon_switch.png", False),
    ]
    
    for side, output_key, data_key, sheet, loops in SPRITE_VARIANTS:
        side_data = spritesheet_data.get(f"{mon_name_lower}_{side}.gif", {})
        if not side_data:
            continue
            
        # For idle animations, use root-level frames; for switch animations, use nested data
        source = side_data if data_key is None else side_data.get(data_key, {})
        if not source or "frames" not in source:
            continue
            
        sprites[output_key] = {
            "spritesheetUrl": f"/assets/mons/all/{sheet}",
            "frames": source["frames"],
            "frameWidth": 96,
            "frameHeight": 96,
            "frameDurationMs": source.get("msPerFrame", 100),
            "loop": loops,
        }
    
    return sprites


def read_mons_data(file_path: str, spritesheet_data: Dict[str, Any]) -> Dict[int, Dict[str, Any]]:
    """Read mons.csv and return a dictionary keyed by mon ID."""
    mons_data = {}
    
    for row in read_csv(file_path):
        mon_id = int(row["Id"])
        mon_name_lower = row["Name"].lower()
        
        mons_data[mon_id] = {
            "id": mon_id,
            "name": row["Name"],
            "flavor": row.get("Flavor", ""),
            "mini": f"/assets/mons/all/{mon_name_lower}_mini.gif",
            "sprites": build_sprites(mon_name_lower, spritesheet_data),
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
    moves_by_mon: Dict[str, List[Dict[str, Any]]] = {}
    
    def parse_int_or_unknown(val: str) -> int | str:
        return int(val) if val.isdigit() else '?'
    
    for row in read_csv(file_path):
        mon_name = row["Mon"]
        moves_by_mon.setdefault(mon_name, []).append({
            "address": f"Address.{to_address_key(row['Name'])}",
            "name": row["Name"],
            "power": parse_int_or_unknown(row["Power"]),
            "stamina": parse_int_or_unknown(row["Stamina"]),
            "accuracy": parse_int_or_unknown(row["Accuracy"]),
            "priority": parse_int_or_unknown(row["Priority"]),
            "type": row["Type"],
            "class": row["Class"],
            "description": row["DevDescription"],
            "extraDataNeeded": row["ExtraData"] == "Yes",
        })
    
    return moves_by_mon


def read_abilities_data(file_path: str) -> Dict[str, Dict[str, str]]:
    """Read abilities.csv and return a dictionary keyed by mon name."""
    return {
        row["Mon"]: {
            "address": f"Address.{to_address_key(row['Name'])}",
            "name": row["Name"],
            "effect": row["Effect"],
        }
        for row in read_csv(file_path)
    }


def combine_data(
    mons_data: Dict[int, Dict[str, Any]],
    moves_by_mon: Dict[str, List[Dict[str, Any]]],
    abilities_by_mon: Dict[str, Dict[str, str]],
) -> Dict[int, Dict[str, Any]]:
    """Combine all data sources into a single structure."""
    for mon_data in mons_data.values():
        mon_name = mon_data["name"]
        mon_data["moves"] = moves_by_mon.get(mon_name, [])
        mon_data["ability"] = abilities_by_mon.get(mon_name, mon_data["ability"])
    return mons_data


def collapse_frame_arrays(json_str: str) -> str:
    """Collapse frame arrays like [[0,0], [96,0]] back to single lines."""
    # Match "frames": followed by a multi-line array of coordinate pairs
    def collapse_match(m: re.Match) -> str:
        content = m.group(1)
        # Remove newlines and excess whitespace, normalize to compact format
        collapsed = re.sub(r"\s+", " ", content).strip()
        # Clean up spacing around brackets
        collapsed = re.sub(r"\[ +", "[", collapsed)
        collapsed = re.sub(r" +\]", "]", collapsed)
        return f'"frames": {collapsed}'
    
    return re.sub(
        r'"frames": (\[\s*\[[\d\s,\[\]]+\])',
        collapse_match,
        json_str,
        flags=re.MULTILINE
    )


def generate_typescript_const(data: Dict[int, Dict[str, Any]], output_file: str):
    """Generate TypeScript const declaration and write to file."""
    json_str = json.dumps(data, indent=2, ensure_ascii=False)
    
    # Collapse frame arrays to single lines
    json_str = collapse_frame_arrays(json_str)
    
    # Replace string keys with integer keys
    json_str = re.sub(r'"(\d+)":', r"\1:", json_str)
    
    # Replace address string references with Address object references
    json_str = re.sub(r'"Address\.([A-Z0-9_]+)"', r"Address.\1", json_str)
    
    # Replace string values with enum references
    ENUM_REPLACEMENTS = {
        "Type": ["Yin", "Yang", "Earth", "Liquid", "Fire", "Metal", "Ice", 
                 "Nature", "Lightning", "Mythic", "Air", "Math", "Cyber", "Wild", "Cosmic"],
        "MoveClass": ["Physical", "Special", "Other", "Self"],
    }
    for enum_name, values in ENUM_REPLACEMENTS.items():
        for val in values:
            json_str = json_str.replace(f'"{val}"', f"{enum_name}.{val}")

    typescript_content = f"""// Auto-generated type file
import {{ Address }} from './address';
import {{ LowercaseHex, Type }} from '../types/structs';
import {{ SpriteAnimationConfig }} from '../types/animation';

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
  readonly mini: string;
  readonly sprites: {{
    readonly frontIdle: SpriteAnimationConfig;
    readonly frontSwitchIn: SpriteAnimationConfig;
    readonly frontSwitchOut: SpriteAnimationConfig;
    readonly backIdle: SpriteAnimationConfig;
    readonly backSwitchIn: SpriteAnimationConfig;
    readonly backSwitchOut: SpriteAnimationConfig;
  }};
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

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(typescript_content)


def main():
    """Main function to orchestrate the data combination."""
    base_path = Path(__file__).parent
    
    files = {
        "mons": base_path / "mons.csv",
        "moves": base_path / "moves.csv",
        "abilities": base_path / "abilities.csv",
        "spritesheet": base_path / "imgs" / "spritesheet.json",
    }
    
    # Determine output location
    game_dir = base_path.parent.parent
    munch_output = game_dir / "munch" / "src" / "app" / "data" / "mon.ts"
    output_file = munch_output if munch_output.parent.exists() else base_path / "mon_data.ts"
    print(f"Output target: {output_file}")
    
    # Verify all input files exist
    missing = [name for name, path in files.items() if not path.exists()]
    if missing:
        print(f"Error: Missing files: {', '.join(missing)}")
        return
    
    print("Reading CSV files and spritesheet data...")
    
    spritesheet_data = read_json(str(files["spritesheet"]))
    mons_data = read_mons_data(str(files["mons"]), spritesheet_data)
    moves_by_mon = read_moves_data(str(files["moves"]))
    abilities_by_mon = read_abilities_data(str(files["abilities"]))
    
    print(f"Loaded {len(mons_data)} mons, moves for {len(moves_by_mon)} mons, abilities for {len(abilities_by_mon)} mons")
    
    combined_data = combine_data(mons_data, moves_by_mon, abilities_by_mon)
    generate_typescript_const(combined_data, str(output_file))
    
    print(f"✅ Generated TypeScript const in {output_file}")


if __name__ == "__main__":
    main()