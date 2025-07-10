import re

def convert_file(input_file, output_file):
    with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
        for line in infile:

            # Split the line into key and value
            key, value = line.strip().split('=')
            
            # Convert the key to uppercase and remove any non-alphanumeric characters
            key = re.sub(r'[^A-Z0-9_]', '', key.upper())
            
            # Convert the value to lowercase
            value = value.lower()
            
            # Write the converted line to the output file
            outfile.write(f"{key}: '{value}' as LowercaseHex,\n")

# Usage
input_file = 'output.txt'  # Replace with your input file name
output_file = 'ts.txt'  # Replace with your desired output file name

convert_file(input_file, output_file)
print(f"Conversion complete. Output written to {output_file}")