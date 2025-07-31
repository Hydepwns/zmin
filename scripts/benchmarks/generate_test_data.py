#!/usr/bin/env python3
"""Generate test JSON datasets for performance benchmarking."""

import json
import os
import random
import string

def generate_random_string(length):
    """Generate a random string of specified length."""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_nested_object(depth, max_keys=5):
    """Generate a nested JSON object."""
    if depth == 0:
        return generate_random_string(random.randint(5, 20))
    
    obj = {}
    num_keys = random.randint(1, max_keys)
    
    for _ in range(num_keys):
        key = generate_random_string(random.randint(5, 15))
        if random.random() < 0.3:  # 30% chance of array
            obj[key] = [generate_nested_object(depth - 1) for _ in range(random.randint(1, 5))]
        elif random.random() < 0.5:  # 50% chance of nested object
            obj[key] = generate_nested_object(depth - 1)
        else:  # Simple value
            value_type = random.choice(['string', 'number', 'boolean', 'null'])
            if value_type == 'string':
                obj[key] = generate_random_string(random.randint(10, 50))
            elif value_type == 'number':
                obj[key] = random.uniform(-1000, 1000)
            elif value_type == 'boolean':
                obj[key] = random.choice([True, False])
            else:
                obj[key] = None
    
    return obj

def generate_dataset(name, target_size_mb):
    """Generate a JSON dataset of approximately the target size."""
    print(f"Generating {name} dataset (~{target_size_mb}MB)...")
    
    # Generate data until we reach target size
    data = {
        "metadata": {
            "dataset": name,
            "version": "1.0",
            "generated": "2025-07-26"
        },
        "items": []
    }
    
    current_size = 0
    target_bytes = target_size_mb * 1024 * 1024
    
    while current_size < target_bytes:
        item = {
            "id": len(data["items"]),
            "type": random.choice(["user", "product", "order", "event"]),
            "timestamp": f"2025-07-26T{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}Z",
            "data": generate_nested_object(random.randint(2, 5))
        }
        
        data["items"].append(item)
        
        # Estimate current size
        if len(data["items"]) % 100 == 0:
            current_size = len(json.dumps(data))
            print(f"  Progress: {current_size / target_bytes * 100:.1f}%")
    
    # Write to file with pretty printing (includes whitespace to minify)
    output_path = f"benchmarks/datasets/{name}.json"
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)
    
    actual_size = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  Generated {output_path} ({actual_size:.2f}MB)")

def main():
    """Generate benchmark datasets."""
    os.makedirs("benchmarks/datasets", exist_ok=True)
    
    # Generate datasets of different sizes
    datasets = [
        ("small", 0.1),    # 100KB
        ("medium", 1),     # 1MB
        ("large", 10),     # 10MB
    ]
    
    for name, size_mb in datasets:
        generate_dataset(name, size_mb)
    
    print("\nDataset generation complete!")

if __name__ == "__main__":
    main()