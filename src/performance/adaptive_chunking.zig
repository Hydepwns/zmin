// Adaptive chunk sizing based on profiling results
const std = @import("std");

pub const AdaptiveChunking = struct {
    pub fn calculateOptimalChunkSize(file_size: usize, thread_count: usize) usize {
        // Based on profiling results, here are the key patterns:
        //
        // Small files (< 10MB):
        // - Prefer smaller chunks (16-64KB) for better parallelization
        // - Very large chunks hurt performance due to poor load balancing
        //
        // Medium files (10-50MB):
        // - 64-256KB chunks are optimal
        // - Balance between parallelization and overhead
        //
        // Large files (> 50MB):
        // - 256KB-4MB chunks work best
        // - Focus on minimizing synchronization overhead
        
        const mb = 1024 * 1024;
        const kb = 1024;
        
        // Handle edge cases
        if (thread_count <= 1) {
            return file_size; // Single threaded
        }
        
        if (file_size < 64 * kb) {
            return file_size / thread_count; // Very small files
        }
        
        // Calculate base chunk size categories
        if (file_size < 10 * mb) {
            // Small files: prefer 16-64KB chunks
            return if (thread_count <= 4) 64 * kb else 16 * kb;
        } else if (file_size < 50 * mb) {
            // Medium files: prefer 64-256KB chunks
            if (thread_count <= 4) {
                return 256 * kb;
            } else if (thread_count <= 8) {
                return 64 * kb;
            } else {
                return 16 * kb; // Many threads on medium files
            }
        } else {
            // Large files: prefer 256KB-4MB chunks
            if (thread_count <= 4) {
                return 4 * mb; // Larger chunks for fewer threads
            } else if (thread_count <= 8) {
                return 256 * kb; // Balanced
            } else {
                return 64 * kb; // Smaller chunks for many threads
            }
        }
    }
    
    // Calculate number of chunks ensuring good load balancing
    pub fn calculateChunkCount(file_size: usize, thread_count: usize, chunk_size: usize) usize {
        const base_chunks = (file_size + chunk_size - 1) / chunk_size;
        
        // Ensure we have at least 2x threads worth of chunks for load balancing
        const min_chunks = thread_count * 2;
        
        return @max(base_chunks, min_chunks);
    }
    
    // Get performance estimates based on profiling data
    pub fn getPerformanceEstimate(file_size: usize, thread_count: usize, chunk_size: usize) PerformanceEstimate {
        const mb = 1024 * 1024;
        const kb = 1024;
        
        // Base single-threaded performance (from profiling)
        const base_throughput: f64 = if (file_size < 10 * mb) 150.0 else 170.0; // MB/s
        
        // Calculate efficiency based on chunk size
        var efficiency: f64 = 1.0;
        
        if (file_size < 10 * mb) {
            // Small files benefit from smaller chunks
            if (chunk_size <= 64 * kb) {
                efficiency = 0.95;
            } else if (chunk_size <= 256 * kb) {
                efficiency = 0.90;
            } else {
                efficiency = 0.75; // Large chunks hurt small files
            }
        } else if (file_size < 50 * mb) {
            // Medium files
            if (chunk_size >= 16 * kb and chunk_size <= 256 * kb) {
                efficiency = 0.95;
            } else if (chunk_size <= 1 * mb) {
                efficiency = 0.90;
            } else {
                efficiency = 0.80;
            }
        } else {
            // Large files
            if (chunk_size >= 64 * kb and chunk_size <= 4 * mb) {
                efficiency = 0.95;
            } else if (chunk_size >= 16 * kb and chunk_size <= 16 * mb) {
                efficiency = 0.90;
            } else {
                efficiency = 0.75;
            }
        }
        
        // Thread scaling efficiency (diminishing returns)
        var thread_efficiency: f64 = 1.0;
        if (thread_count <= 2) {
            thread_efficiency = 0.90;
        } else if (thread_count <= 4) {
            thread_efficiency = 0.85;
        } else if (thread_count <= 8) {
            thread_efficiency = 0.80;
        } else if (thread_count <= 16) {
            thread_efficiency = 0.70;
        } else {
            thread_efficiency = 0.60;
        }
        
        const estimated_throughput = base_throughput * @as(f64, @floatFromInt(thread_count)) * 
                                   efficiency * thread_efficiency;
        
        return PerformanceEstimate{
            .estimated_throughput_mb_s = estimated_throughput,
            .chunk_efficiency = efficiency,
            .thread_efficiency = thread_efficiency,
            .recommended = isRecommendedConfiguration(file_size, thread_count, chunk_size),
        };
    }
    
    fn isRecommendedConfiguration(file_size: usize, thread_count: usize, chunk_size: usize) bool {
        const optimal_chunk_size = calculateOptimalChunkSize(file_size, thread_count);
        
        // Allow some tolerance around the optimal size
        const min_acceptable = optimal_chunk_size / 2;
        const max_acceptable = optimal_chunk_size * 2;
        
        return chunk_size >= min_acceptable and chunk_size <= max_acceptable;
    }
    
    pub const PerformanceEstimate = struct {
        estimated_throughput_mb_s: f64,
        chunk_efficiency: f64,
        thread_efficiency: f64,
        recommended: bool,
    };
};