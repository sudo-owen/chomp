import re

# def snake_case(s):
#     # Convert camelCase or PascalCase to snake_case
#     s = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', s)
#     return re.sub('([a-z0-9])([A-Z])', r'\1_\2', s).lower().replace(" ", "")

def parse_deploy_data_array(content):
    """Parse the DeployData array structure from the input file"""
    # Remove whitespace and newlines
    content = content.strip()

    # Extract individual DeployData objects using regex
    deploy_data_pattern = r'DeployData\(\{\s*name:\s*"([^"]+)",\s*contractAddress:\s*(0x[a-fA-F0-9]+)\s*\}\)'
    matches = re.findall(deploy_data_pattern, content)

    return matches

def process_file(input_file, output_file):
    with open(input_file, 'r') as f:
        content = f.read()

    output = []

    # Try to parse as DeployData array structure first
    deploy_data_matches = parse_deploy_data_array(content)
    if deploy_data_matches:
        for name, address in deploy_data_matches:
            name = name.upper().replace(" ", "_").replace("-", "_")
            output.append(f"{name}={address}")

    with open(output_file, 'w') as f:
        f.write('\n'.join(output))

# Usage
input_file = 'processing/input.txt'
output_file = 'processing/output.txt'
process_file(input_file, output_file)
print(f"Conversion complete. Output written to {output_file}")