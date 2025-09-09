#!/usr/bin/env python3
"""
Script to validate move contracts against CSV data.
Checks that contract implementations match the expected values from moves.csv.
"""

import csv
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass

@dataclass
class MoveData:
    """Data structure for move information from CSV"""
    name: str
    mon: str
    power: int
    stamina: int
    accuracy: int
    priority: int
    move_type: str
    move_class: str
    description: str
    extra_data: str

@dataclass
class ContractData:
    """Data structure for extracted contract information"""
    file_path: str
    power: Optional[int] = None
    stamina: Optional[int] = None
    priority: Optional[int] = None
    move_type: Optional[str] = None
    move_class: Optional[str] = None
    is_standard_attack: bool = False
    is_custom_implementation: bool = False

class MoveValidator:
    """Main validator class for checking move contracts against CSV data"""
    
    # Constants from the codebase
    DEFAULT_PRIORITY = 3
    
    # Type enum mapping
    TYPE_MAPPING = {
        'Yin': 'Type.Yin',
        'Yang': 'Type.Yang', 
        'Earth': 'Type.Earth',
        'Water': 'Type.Water',
        'Fire': 'Type.Fire',
        'Metal': 'Type.Metal',
        'Ice': 'Type.Ice',
        'Nature': 'Type.Nature',
        'Lightning': 'Type.Lightning',
        'Mythic': 'Type.Mythic',
        'Air': 'Type.Air',
        'Mind': 'Type.Mind',
        'Cyber': 'Type.Cyber',
        'Wild': 'Type.Wild',
        'Cosmic': 'Type.Cosmic',
        'None': 'Type.None'
    }
    
    # MoveClass enum mapping
    CLASS_MAPPING = {
        'Physical': 'MoveClass.Physical',
        'Special': 'MoveClass.Special',
        'Self': 'MoveClass.Self',
        'Other': 'MoveClass.Other'
    }
    
    def __init__(self, csv_path: str, src_path: str):
        self.csv_path = csv_path
        self.src_path = src_path
        self.moves_data: Dict[str, MoveData] = {}
        self.validation_results: List[Dict[str, Any]] = []
        
    def normalize_move_name(self, name: str) -> str:
        """Convert move name to CamelCase with spaces and punctuation removed"""
        # Remove punctuation and split on spaces
        words = re.sub(r'[^\w\s]', '', name).split()
        # Convert to CamelCase
        return ''.join(word.capitalize() for word in words)
    
    def load_csv_data(self) -> None:
        """Load and parse the moves CSV file"""
        with open(self.csv_path, 'r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                move_data = MoveData(
                    name=row['Name'],
                    mon=row['Mon'],
                    power=int(row['Power']),
                    stamina=int(row['Stamina']),
                    accuracy=int(row['Accuracy']),
                    priority=int(row['Priority']),
                    move_type=row['Type'],
                    move_class=row['Class'],
                    description=row['Description'],
                    extra_data=row['ExtraData']
                )
                normalized_name = self.normalize_move_name(move_data.name)
                self.moves_data[normalized_name] = move_data
    
    def find_contract_file(self, move_name: str) -> Optional[str]:
        """Find the contract file for a given move name"""
        contract_name = f"{move_name}.sol"
        
        # Search recursively through src directory
        for root, dirs, files in os.walk(self.src_path):
            if contract_name in files:
                return os.path.join(root, contract_name)
        
        return None

    def parse_contract_file(self, file_path: str) -> ContractData:
        """Parse a Solidity contract file to extract move data"""
        contract_data = ContractData(file_path=file_path)

        with open(file_path, 'r', encoding='utf-8') as file:
            content = file.read()

        # Check if it inherits from StandardAttack
        if 'StandardAttack' in content and 'is StandardAttack' in content:
            contract_data.is_standard_attack = True
            contract_data = self._parse_standard_attack(content, contract_data)
        elif 'IMoveSet' in content and 'is IMoveSet' in content:
            contract_data.is_custom_implementation = True
            contract_data = self._parse_custom_implementation(content, contract_data)

        return contract_data

    def _parse_standard_attack(self, content: str, contract_data: ContractData) -> ContractData:
        """Parse StandardAttack constructor parameters"""
        # Find ATTACK_PARAMS block
        attack_params_match = re.search(r'ATTACK_PARAMS\s*\(\s*\{([^}]+)\}\s*\)', content, re.DOTALL)
        if not attack_params_match:
            return contract_data

        params_block = attack_params_match.group(1)

        # Extract individual parameters
        contract_data.power = self._extract_param_value(params_block, 'BASE_POWER')
        contract_data.stamina = self._extract_param_value(params_block, 'STAMINA_COST')
        contract_data.priority = self._extract_priority_value(params_block)
        contract_data.move_type = self._extract_enum_value(params_block, 'MOVE_TYPE', 'Type')
        contract_data.move_class = self._extract_enum_value(params_block, 'MOVE_CLASS', 'MoveClass')

        return contract_data

    def _parse_custom_implementation(self, content: str, contract_data: ContractData) -> ContractData:
        """Parse custom IMoveSet implementation"""
        # Look for constant declarations
        contract_data.power = self._extract_constant_value(content, 'BASE_POWER')

        # Look for function implementations
        contract_data.stamina = self._extract_function_return_value(content, 'stamina')
        contract_data.priority = self._extract_function_return_value(content, 'priority')
        contract_data.move_type = self._extract_function_enum_return(content, 'moveType', 'Type')
        contract_data.move_class = self._extract_function_enum_return(content, 'moveClass', 'MoveClass')

        return contract_data

    def _extract_param_value(self, params_block: str, param_name: str) -> Optional[int]:
        """Extract numeric parameter value from ATTACK_PARAMS block"""
        pattern = rf'{param_name}:\s*(\d+)'
        match = re.search(pattern, params_block)
        return int(match.group(1)) if match else None

    def _extract_priority_value(self, params_block: str) -> Optional[int]:
        """Extract priority value, handling DEFAULT_PRIORITY expressions"""
        pattern = r'PRIORITY:\s*([^,\n]+)'
        match = re.search(pattern, params_block)
        if not match:
            return None

        priority_expr = match.group(1).strip()

        # Handle DEFAULT_PRIORITY expressions
        if 'DEFAULT_PRIORITY' in priority_expr:
            return self._evaluate_priority_expression(priority_expr)

        # Try to parse as direct number
        try:
            return int(priority_expr)
        except ValueError:
            return None

    def _evaluate_priority_expression(self, expr: str) -> Optional[int]:
        """Evaluate arithmetic expressions involving DEFAULT_PRIORITY"""
        # Replace DEFAULT_PRIORITY with its actual value
        expr_with_value = expr.replace('DEFAULT_PRIORITY', str(self.DEFAULT_PRIORITY))

        # Remove whitespace
        expr_with_value = expr_with_value.replace(' ', '')

        # Validate that the expression only contains safe characters
        if not re.match(r'^[\d+\-*/()]+$', expr_with_value):
            return None

        try:
            # Safely evaluate the arithmetic expression
            return int(eval(expr_with_value))
        except (ValueError, SyntaxError, ZeroDivisionError):
            return None

    def _extract_enum_value(self, params_block: str, param_name: str, enum_type: str) -> Optional[str]:
        """Extract enum parameter value from ATTACK_PARAMS block"""
        pattern = rf'{param_name}:\s*{enum_type}\.(\w+)'
        match = re.search(pattern, params_block)
        return match.group(1) if match else None

    def _extract_constant_value(self, content: str, constant_name: str) -> Optional[int]:
        """Extract constant value from contract"""
        pattern = rf'{constant_name}\s*=\s*(\d+)'
        match = re.search(pattern, content)
        return int(match.group(1)) if match else None

    def _extract_function_return_value(self, content: str, function_name: str) -> Optional[int]:
        """Extract return value from function implementation"""
        # Look for function that returns a constant
        pattern = rf'function\s+{function_name}\s*\([^)]*\)\s*[^{{]*\{{\s*return\s+(\d+);'
        match = re.search(pattern, content, re.DOTALL)
        if match:
            return int(match.group(1))

        # Look for function that returns a constant variable or expression
        pattern = rf'function\s+{function_name}\s*\([^)]*\)\s*[^{{]*\{{\s*return\s+([^;]+);'
        match = re.search(pattern, content, re.DOTALL)
        if match:
            return_expr = match.group(1).strip()

            # Handle known constants
            if return_expr == 'DEFAULT_PRIORITY':
                return self.DEFAULT_PRIORITY
            elif 'DEFAULT_PRIORITY' in return_expr:
                return self._evaluate_priority_expression(return_expr)

            # Try to extract as local constant
            if re.match(r'^[A-Z_]+$', return_expr):
                local_value = self._extract_constant_value(content, return_expr)
                if local_value is not None:
                    return local_value

            # Try to parse as direct number
            try:
                return int(return_expr)
            except ValueError:
                pass

        return None

    def _extract_function_enum_return(self, content: str, function_name: str, enum_type: str) -> Optional[str]:
        """Extract enum return value from function implementation"""
        pattern = rf'function\s+{function_name}\s*\([^)]*\)\s*[^{{]*\{{\s*return\s+{enum_type}\.(\w+);'
        match = re.search(pattern, content, re.DOTALL)
        return match.group(1) if match else None

    def csv_priority_to_contract_priority(self, csv_priority: int) -> int:
        """Convert CSV priority (0-based) to contract priority (DEFAULT_PRIORITY-based)"""
        return self.DEFAULT_PRIORITY + csv_priority

    def validate_move(self, move_name: str, move_data: MoveData, contract_data: ContractData) -> Dict[str, Any]:
        """Validate a single move against its contract"""
        result = {
            'move_name': move_data.name,
            'normalized_name': move_name,
            'contract_file': contract_data.file_path,
            'is_standard_attack': contract_data.is_standard_attack,
            'is_custom_implementation': contract_data.is_custom_implementation,
            'errors': [],
            'warnings': []
        }

        # Skip power validation for 0-power moves
        if move_data.power > 0:
            if contract_data.power is None:
                result['errors'].append(f"Power not found in contract (expected: {move_data.power})")
            elif contract_data.power != move_data.power:
                result['errors'].append(f"Power mismatch: contract={contract_data.power}, csv={move_data.power}")

        # Validate stamina
        if contract_data.stamina is None:
            result['errors'].append(f"Stamina not found in contract (expected: {move_data.stamina})")
        elif contract_data.stamina != move_data.stamina:
            result['errors'].append(f"Stamina mismatch: contract={contract_data.stamina}, csv={move_data.stamina}")

        # Validate priority
        expected_priority = self.csv_priority_to_contract_priority(move_data.priority)
        if contract_data.priority is None:
            result['errors'].append(f"Priority not found in contract (expected: {expected_priority})")
        elif contract_data.priority != expected_priority:
            result['errors'].append(f"Priority mismatch: contract={contract_data.priority}, csv={move_data.priority} (expected contract value: {expected_priority})")

        # Validate move type
        if contract_data.move_type is None:
            result['errors'].append(f"Move type not found in contract (expected: {move_data.move_type})")
        elif contract_data.move_type != move_data.move_type:
            result['errors'].append(f"Move type mismatch: contract={contract_data.move_type}, csv={move_data.move_type}")

        # Validate move class
        if contract_data.move_class is None:
            result['errors'].append(f"Move class not found in contract (expected: {move_data.move_class})")
        elif contract_data.move_class != move_data.move_class:
            result['errors'].append(f"Move class mismatch: contract={contract_data.move_class}, csv={move_data.move_class}")

        return result

    def run_validation(self) -> None:
        """Run validation for all moves"""
        print("Loading CSV data...")
        self.load_csv_data()
        print(f"Loaded {len(self.moves_data)} moves from CSV")

        print("\nSearching for contract files...")
        found_contracts = 0
        missing_contracts = []

        for move_name, move_data in self.moves_data.items():
            contract_file = self.find_contract_file(move_name)

            if contract_file is None:
                missing_contracts.append((move_name, move_data.name))
                continue

            found_contracts += 1
            print(f"  Found: {move_name} -> {contract_file}")

            # Parse and validate the contract
            contract_data = self.parse_contract_file(contract_file)
            validation_result = self.validate_move(move_name, move_data, contract_data)
            self.validation_results.append(validation_result)

        print(f"\nFound {found_contracts} contracts, {len(missing_contracts)} missing")

        # Report results
        self.print_summary()
        self.print_detailed_errors()

        if missing_contracts:
            self.print_missing_contracts(missing_contracts)

    def print_summary(self) -> None:
        """Print a condensed summary of validation results"""
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)

        total_moves = len(self.validation_results)
        moves_with_errors = sum(1 for result in self.validation_results if result['errors'])
        moves_with_warnings = sum(1 for result in self.validation_results if result['warnings'])

        standard_attack_count = sum(1 for result in self.validation_results if result['is_standard_attack'])
        custom_implementation_count = sum(1 for result in self.validation_results if result['is_custom_implementation'])

        print(f"Total moves validated: {total_moves}")
        print(f"Moves with errors: {moves_with_errors}")
        print(f"Moves with warnings: {moves_with_warnings}")
        print(f"StandardAttack implementations: {standard_attack_count}")
        print(f"Custom IMoveSet implementations: {custom_implementation_count}")

        if moves_with_errors == 0:
            print("\n✅ All validations passed!")
        else:
            print(f"\n❌ {moves_with_errors} moves have validation errors")

    def print_detailed_errors(self) -> None:
        """Print detailed error information"""
        moves_with_issues = [result for result in self.validation_results
                           if result['errors'] or result['warnings']]

        if not moves_with_issues:
            return

        print("\n" + "="*80)
        print("DETAILED ERRORS AND WARNINGS")
        print("="*80)

        for result in moves_with_issues:
            print(f"\n📁 {result['move_name']} ({result['normalized_name']})")
            print(f"   File: {result['contract_file']}")
            print(f"   Type: {'StandardAttack' if result['is_standard_attack'] else 'Custom IMoveSet'}")

            if result['errors']:
                print("   ❌ Errors:")
                for error in result['errors']:
                    print(f"      • {error}")

            if result['warnings']:
                print("   ⚠️  Warnings:")
                for warning in result['warnings']:
                    print(f"      • {warning}")

    def print_missing_contracts(self, missing_contracts: List[Tuple[str, str]]) -> None:
        """Print information about missing contract files"""
        print("\n" + "="*80)
        print("MISSING CONTRACTS")
        print("="*80)

        for normalized_name, original_name in missing_contracts:
            print(f"❌ {original_name} -> {normalized_name}.sol (not found)")


def main():
    """Main entry point"""
    import sys

    # Default paths (relative to processing folder)
    csv_path = "../drool/moves.csv"
    src_path = "../src/"

    # Allow command line arguments
    if len(sys.argv) > 1:
        csv_path = sys.argv[1]
    if len(sys.argv) > 2:
        src_path = sys.argv[2]

    # Validate paths exist
    if not os.path.exists(csv_path):
        print(f"Error: CSV file not found: {csv_path}")
        sys.exit(1)

    if not os.path.exists(src_path):
        print(f"Error: Source directory not found: {src_path}")
        sys.exit(1)

    # Run validation
    validator = MoveValidator(csv_path, src_path)
    validator.run_validation()


if __name__ == "__main__":
    main()
