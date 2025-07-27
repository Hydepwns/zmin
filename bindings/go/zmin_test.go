package zmin

import (
	"testing"
)

func TestMinify(t *testing.T) {
	input := `{
		"name": "John Doe",
		"age": 30,
		"city": "New York",
		"hobbies": ["reading", "swimming", "coding"]
	}`

	output, err := Minify(input)
	if err != nil {
		t.Fatalf("Minify failed: %v", err)
	}

	expected := `{"name":"John Doe","age":30,"city":"New York","hobbies":["reading","swimming","coding"]}`
	if output != expected {
		t.Errorf("Expected %q, got %q", expected, output)
	}
}

func TestMinifyWithMode(t *testing.T) {
	input := `{"key": "value", "array": [1, 2, 3]}`

	// Test all modes
	modes := []ProcessingMode{ECO, SPORT, TURBO}
	for _, mode := range modes {
		output, err := MinifyWithMode(input, mode)
		if err != nil {
			t.Errorf("MinifyWithMode failed for mode %d: %v", mode, err)
		}
		if output == "" {
			t.Errorf("Empty output for mode %d", mode)
		}
	}
}

func TestValidate(t *testing.T) {
	// Test valid JSON
	valid := `{"name": "John", "age": 30}`
	if !Validate(valid) {
		t.Error("Valid JSON was not recognized as valid")
	}

	// Test invalid JSON
	invalid := `{"name": "John", "age": 30,}`
	if Validate(invalid) {
		t.Error("Invalid JSON was recognized as valid")
	}
}

func TestMinifyBytes(t *testing.T) {
	input := []byte(`{"key": "value"}`)
	output, err := MinifyBytes(input, SPORT)
	if err != nil {
		t.Fatalf("MinifyBytes failed: %v", err)
	}

	expected := []byte(`{"key":"value"}`)
	if string(output) != string(expected) {
		t.Errorf("Expected %q, got %q", expected, output)
	}
}

func TestVersion(t *testing.T) {
	version := Version()
	if version == "" {
		t.Error("Version should not be empty")
	}
}

func TestMinifier(t *testing.T) {
	minifier := NewMinifier(TURBO)
	input := `{"test": true}`

	output, err := minifier.Minify(input)
	if err != nil {
		t.Fatalf("Minifier.Minify failed: %v", err)
	}

	if output == "" {
		t.Error("Minifier output should not be empty")
	}
}

func TestErrorHandling(t *testing.T) {
	// Test invalid JSON
	_, err := Minify(`{"invalid": json}`)
	if err == nil {
		t.Error("Expected error for invalid JSON")
	}
}

func BenchmarkMinify(b *testing.B) {
	input := `{
		"name": "John Doe",
		"age": 30,
		"city": "New York",
		"hobbies": ["reading", "swimming", "coding"],
		"address": {
			"street": "123 Main St",
			"city": "New York",
			"zip": "10001"
		}
	}`

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := Minify(input)
		if err != nil {
			b.Fatalf("Minify failed: %v", err)
		}
	}
}

func BenchmarkMinifyWithMode(b *testing.B) {
	input := `{"key": "value", "array": [1, 2, 3, 4, 5]}`

	b.Run("ECO", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, err := MinifyWithMode(input, ECO)
			if err != nil {
				b.Fatalf("MinifyWithMode ECO failed: %v", err)
			}
		}
	})

	b.Run("SPORT", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, err := MinifyWithMode(input, SPORT)
			if err != nil {
				b.Fatalf("MinifyWithMode SPORT failed: %v", err)
			}
		}
	})

	b.Run("TURBO", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, err := MinifyWithMode(input, TURBO)
			if err != nil {
				b.Fatalf("MinifyWithMode TURBO failed: %v", err)
			}
		}
	})
} 