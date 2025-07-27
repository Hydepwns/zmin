// Package zmin provides Go bindings for the zmin high-performance JSON minifier.
package zmin

/*
#cgo LDFLAGS: -L. -lzmin
#include <stdlib.h>
#include <stdint.h>

// Result structure from C API
typedef struct {
    char* data;
    size_t size;
    int error_code;
} zmin_result_t;

// Function declarations
void zmin_init(void);
zmin_result_t zmin_minify(const char* input, size_t input_size);
zmin_result_t zmin_minify_mode(const char* input, size_t input_size, int mode);
int zmin_validate(const char* input, size_t input_size);
void zmin_free_result(zmin_result_t* result);
const char* zmin_get_version(void);
const char* zmin_get_error_message(int error_code);
*/
import "C"
import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"unsafe"
)

// ProcessingMode represents the JSON processing mode
type ProcessingMode int

const (
	// ECO mode - Memory-efficient mode (64KB limit)
	ECO ProcessingMode = 0
	// SPORT mode - Balanced mode (default)
	SPORT ProcessingMode = 1
	// TURBO mode - Maximum performance mode
	TURBO ProcessingMode = 2
)

var (
	// ErrInvalidJSON is returned when the input is not valid JSON
	ErrInvalidJSON = errors.New("invalid JSON")
	// ErrOutOfMemory is returned when memory allocation fails
	ErrOutOfMemory = errors.New("out of memory")
	// ErrInvalidMode is returned when an invalid processing mode is specified
	ErrInvalidMode = errors.New("invalid mode")
	// ErrUnknown is returned for unknown errors
	ErrUnknown = errors.New("unknown error")
)

var initOnce sync.Once

// init initializes the zmin library
func init() {
	initOnce.Do(func() {
		C.zmin_init()
	})
}

// Version returns the zmin library version
func Version() string {
	return C.GoString(C.zmin_get_version())
}

// Minify minifies JSON data using the default SPORT mode
func Minify(input interface{}) (string, error) {
	return MinifyWithMode(input, SPORT)
}

// MinifyWithMode minifies JSON data using the specified processing mode
func MinifyWithMode(input interface{}, mode ProcessingMode) (string, error) {
	// Convert input to string
	jsonStr, err := toJSONString(input)
	if err != nil {
		return "", err
	}

	// Convert to C string
	cInput := C.CString(jsonStr)
	defer C.free(unsafe.Pointer(cInput))

	// Call C function
	result := C.zmin_minify_mode(cInput, C.size_t(len(jsonStr)), C.int(mode))
	defer C.zmin_free_result(&result)

	// Check for errors
	if result.error_code != 0 {
		return "", getError(result.error_code)
	}

	// Convert result to Go string
	output := C.GoStringN(result.data, C.int(result.size))
	return output, nil
}

// Validate checks if the input is valid JSON
func Validate(input interface{}) bool {
	// Convert input to string
	jsonStr, err := toJSONString(input)
	if err != nil {
		return false
	}

	// Convert to C string
	cInput := C.CString(jsonStr)
	defer C.free(unsafe.Pointer(cInput))

	// Call C function
	errorCode := C.zmin_validate(cInput, C.size_t(len(jsonStr)))
	return errorCode == 0
}

// MinifyBytes minifies JSON data from bytes
func MinifyBytes(input []byte, mode ProcessingMode) ([]byte, error) {
	output, err := MinifyWithMode(string(input), mode)
	if err != nil {
		return nil, err
	}
	return []byte(output), nil
}

// MinifyReader minifies JSON data from an io.Reader
func MinifyReader(r io.Reader, mode ProcessingMode) (string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return "", err
	}
	return MinifyWithMode(string(data), mode)
}

// MinifyFile minifies a JSON file
func MinifyFile(inputPath, outputPath string, mode ProcessingMode) error {
	// Read input file
	input, err := os.ReadFile(inputPath)
	if err != nil {
		return err
	}

	// Minify
	output, err := MinifyWithMode(string(input), mode)
	if err != nil {
		return err
	}

	// Write output file
	return os.WriteFile(outputPath, []byte(output), 0644)
}

// ValidateFile validates a JSON file
func ValidateFile(filePath string) bool {
	input, err := os.ReadFile(filePath)
	if err != nil {
		return false
	}
	return Validate(string(input))
}

// toJSONString converts various input types to JSON string
func toJSONString(input interface{}) (string, error) {
	switch v := input.(type) {
	case string:
		return v, nil
	case []byte:
		return string(v), nil
	case io.Reader:
		data, err := io.ReadAll(v)
		if err != nil {
			return "", err
		}
		return string(data), nil
	default:
		// For other types, use json.Marshal
		data, err := json.Marshal(v)
		if err != nil {
			return "", err
		}
		return string(data), nil
	}
}

// getError converts C error code to Go error
func getError(errorCode C.int) error {
	switch errorCode {
	case -1:
		return ErrInvalidJSON
	case -2:
		return ErrOutOfMemory
	case -3:
		return ErrInvalidMode
	default:
		errMsg := C.GoString(C.zmin_get_error_message(errorCode))
		return fmt.Errorf("%w: %s", ErrUnknown, errMsg)
	}
}

// Minifier provides a reusable minifier instance
type Minifier struct {
	mode ProcessingMode
}

// NewMinifier creates a new minifier with the specified mode
func NewMinifier(mode ProcessingMode) *Minifier {
	return &Minifier{mode: mode}
}

// Minify minifies JSON using the configured mode
func (m *Minifier) Minify(input interface{}) (string, error) {
	return MinifyWithMode(input, m.mode)
}

// MinifyBytes minifies JSON bytes using the configured mode
func (m *Minifier) MinifyBytes(input []byte) ([]byte, error) {
	return MinifyBytes(input, m.mode)
}

// MinifyReader minifies JSON from reader using the configured mode
func (m *Minifier) MinifyReader(r io.Reader) (string, error) {
	return MinifyReader(r, m.mode)
}

// MinifyFile minifies a file using the configured mode
func (m *Minifier) MinifyFile(inputPath, outputPath string) error {
	return MinifyFile(inputPath, outputPath, m.mode)
}

// Default minifiers for each mode
var (
	EcoMinifier   = NewMinifier(ECO)
	SportMinifier = NewMinifier(SPORT)
	TurboMinifier = NewMinifier(TURBO)
)