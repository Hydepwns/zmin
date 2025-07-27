#!/usr/bin/env python3
"""
Simple test for zmin Python bindings
"""

import sys
import os

# Add the parent directory to the path so we can import zmin
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import zmin
    print("✓ zmin module imported successfully")
except ImportError as e:
    print(f"✗ Failed to import zmin: {e}")
    sys.exit(1)

def test_basic_functionality():
    """Test basic minification functionality"""
    print("\nTesting basic functionality...")
    
    # Test input
    test_json = '''
    {
        "name": "John Doe",
        "age": 30,
        "city": "New York",
        "hobbies": ["reading", "swimming", "coding"]
    }
    '''
    
    try:
        # Test minification
        minified = zmin.minify(test_json)
        print(f"✓ Minification successful: {minified[:50]}...")
        
        # Test validation
        is_valid = zmin.validate(test_json)
        print(f"✓ Validation successful: {is_valid}")
        
        # Test different modes
        eco_result = zmin.minify(test_json, zmin.ProcessingMode.ECO)
        sport_result = zmin.minify(test_json, zmin.ProcessingMode.SPORT)
        turbo_result = zmin.minify(test_json, zmin.ProcessingMode.TURBO)
        
        print(f"✓ All processing modes work")
        
        return True
        
    except Exception as e:
        print(f"✗ Test failed: {e}")
        return False

def test_error_handling():
    """Test error handling"""
    print("\nTesting error handling...")
    
    try:
        # Test invalid JSON
        result = zmin.minify('{"invalid": json}')
        print("✗ Should have raised an error for invalid JSON")
        return False
    except zmin.ZminError:
        print("✓ Properly handled invalid JSON")
    except Exception as e:
        print(f"✗ Unexpected error: {e}")
        return False
    
    return True

def test_version():
    """Test version information"""
    print("\nTesting version information...")
    
    try:
        version = zmin.get_default_instance().get_version()
        print(f"✓ Version: {version}")
        return True
    except Exception as e:
        print(f"✗ Failed to get version: {e}")
        return False

def main():
    """Run all tests"""
    print("zmin Python Bindings Test")
    print("=" * 30)
    
    tests = [
        test_basic_functionality,
        test_error_handling,
        test_version,
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
    
    print(f"\nResults: {passed}/{total} tests passed")
    
    if passed == total:
        print("✓ All tests passed!")
        return 0
    else:
        print("✗ Some tests failed!")
        return 1

if __name__ == "__main__":
    sys.exit(main()) 