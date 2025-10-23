import csv
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import LinearSegmentedColormap

def multiplier_to_bits(m):
    if m == 0:
        return '00'
    if m == 1:
        return '01'
    if m == 2:
        return '10'
    if m == 5:
        return '11'
    else:
        raise ValueError(f"Invalid multiplier: {m}")

def parse_csv_for_solidity(file_path):
    v1 = ''
    v2 = ''
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        # Skip the header row
        next(reader)  
        for row in reader:
            # Skip empty rows
            if not row or all(cell.strip() == '' for cell in row):
                continue
            attacker, defender, multiplier = row
            
            # We prepend each new value so we can use right shifts later to extract out the right one
            if len(v1) < 256:
                v1 = multiplier_to_bits(int(multiplier)) + v1
            else:
                v2 = multiplier_to_bits(int(multiplier)) + v2
    
    # Prepend v2 with zeroes for the rest of it
    v2 = ('0' * 62) + v2
    return (int(v1, 2), int(v2, 2))

def generate_solidity_contract(encoded_uints):
    contract = f"""
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {{ITypeCalculator}} from "./ITypeCalculator.sol";
import "../Enums.sol";

contract TypeCalculator is ITypeCalculator {{
    uint256 private constant MULTIPLIERS_1 = {encoded_uints[0]}; // First 128 type combinations
    uint256 private constant MULTIPLIERS_2 = {encoded_uints[1]}; // Remaining 97 type combinations

    function getTypeEffectiveness(Type attackerType, Type defenderType) external pure returns (uint32) {{
        uint256 index = uint256(attackerType) * 15 + uint256(defenderType);
        uint256 shift;
        uint256 multipliers;
        
        if (index < 128) {{
            shift = index * 2;
            multipliers = MULTIPLIERS_1;
        }} else {{
            shift = (index - 128) * 2;
            multipliers = MULTIPLIERS_2;
        }}
        
        // Return the last 2 bits of the multipliers for the correct shift
        return uint32((multipliers >> shift) & 3);
    }}
}}
"""
    return contract

def read_csv_for_graph(file_path):
    data = {}
    types = set()
    with open(file_path, 'r') as f:
        reader = csv.reader(f)
        next(reader)  # Skip header
        for row in reader:
            if not row or all(cell.strip() == '' for cell in row):
                continue
            attacker, defender, multiplier = row
            attacker = attacker.strip()
            defender = defender.strip()
            types.add(attacker)
            types.add(defender)
            if attacker not in data:
                data[attacker] = {}
            data[attacker][defender] = float(multiplier)
    return data, sorted(list(types))

def create_custom_cmap():
    colors = ['#FF4136', '#FFFFFF', '#2ECC40']
    return LinearSegmentedColormap.from_list("custom", colors, N=256)

def create_chart(data, types):
    n = len(types)
    matrix = np.ones((n, n))
    for i, attacker in enumerate(types):
        for j, defender in enumerate(types):
            if attacker in data and defender in data[attacker]:
                value = data[attacker][defender]
                if value == 5:
                    matrix[i, j] = 0.5
                elif value == 0:
                    matrix[i, j] = 0
                else:
                    matrix[i, j] = value

    fig, ax = plt.subplots(figsize=(15, 15), dpi=300)
    custom_cmap = create_custom_cmap()
    im = ax.imshow(matrix, cmap=custom_cmap, vmin=0, vmax=2)

    ax.set_xticks(np.arange(n))
    ax.set_yticks(np.arange(n))
    
    uppercase_types = [t.upper() for t in types]
    
    ax.set_xticklabels(uppercase_types, fontsize=10, fontweight='bold')
    ax.set_yticklabels(uppercase_types, fontsize=10, fontweight='bold')

    plt.setp(ax.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    # Color-code axis labels
    for i, label in enumerate(ax.get_xticklabels()):
        label.set_color(plt.cm.tab20(i / n))
    for i, label in enumerate(ax.get_yticklabels()):
        label.set_color(plt.cm.tab20(i / n))

    for i in range(n):
        for j in range(n):
            value = matrix[i, j]
            if value == 0.5:
                text = "½"
            elif value == 0:
                text = "0"
            elif value == 2:
                text = "2"
            else:
                text = ""
            ax.text(j, i, text, ha="center", va="center", color="black", fontsize=10, fontweight='bold')

    ax.set_title("Type Effectiveness Chart", fontsize=20, fontweight='bold', pad=20)
    
    # Add a color bar
    cbar = fig.colorbar(im, ax=ax, aspect=30)
    cbar.ax.set_ylabel("Effectiveness", rotation=-90, va="bottom", fontsize=12, fontweight='bold')
    
    # Add grid lines
    ax.set_xticks(np.arange(-.5, n, 1), minor=True)
    ax.set_yticks(np.arange(-.5, n, 1), minor=True)
    ax.grid(which="minor", color="black", linestyle='-', linewidth=1)
    
    fig.tight_layout()
    plt.savefig("types.png", bbox_inches='tight')
    plt.close()

def main():
    csv_file = './data/types.csv'
    encoded_uints = parse_csv_for_solidity(csv_file)
    solidity_contract = generate_solidity_contract(encoded_uints)
    
    with open('../src/types/TypeCalculator.sol', 'w') as f:
        f.write(solidity_contract)

    data, types = read_csv_for_graph(csv_file)
    create_chart(data, types)
    
if __name__ == "__main__":
    main()