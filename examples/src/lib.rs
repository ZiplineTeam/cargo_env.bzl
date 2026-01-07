use openssl::sha::sha256;

/// Computes the SHA256 hash of the input and returns it as a hex string.
pub fn sha256_hex(input: &[u8]) -> String {
    let digest = sha256(input);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

pub mod zstd_example {
    use std::io::{Read, Write};

    /// Compresses data using zstd with the given compression level.
    /// Level ranges from 1 (fastest) to 22 (best compression).
    pub fn compress(data: &[u8], level: i32) -> std::io::Result<Vec<u8>> {
        zstd::encode_all(data, level)
    }

    /// Decompresses zstd-compressed data.
    pub fn decompress(data: &[u8]) -> std::io::Result<Vec<u8>> {
        zstd::decode_all(data)
    }

    /// Compresses data using a streaming encoder.
    pub fn compress_streaming(data: &[u8], level: i32) -> std::io::Result<Vec<u8>> {
        let mut encoder = zstd::stream::Encoder::new(Vec::new(), level)?;
        encoder.write_all(data)?;
        encoder.finish()
    }

    /// Decompresses data using a streaming decoder.
    pub fn decompress_streaming(data: &[u8]) -> std::io::Result<Vec<u8>> {
        let mut decoder = zstd::stream::Decoder::new(data)?;
        let mut output = Vec::new();
        decoder.read_to_end(&mut output)?;
        Ok(output)
    }

    /// Returns compression statistics for the given data.
    pub fn compression_stats(data: &[u8], level: i32) -> std::io::Result<CompressionStats> {
        let compressed = compress(data, level)?;
        let ratio = if compressed.is_empty() {
            0.0
        } else {
            data.len() as f64 / compressed.len() as f64
        };

        Ok(CompressionStats {
            original_size: data.len(),
            compressed_size: compressed.len(),
            compression_ratio: ratio,
        })
    }

    #[derive(Debug)]
    pub struct CompressionStats {
        pub original_size: usize,
        pub compressed_size: usize,
        pub compression_ratio: f64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_hex() {
        let input = b"hello openssl";
        let result = sha256_hex(input);

        // SHA256 produces a 64-character hex string (32 bytes * 2)
        assert_eq!(result.len(), 64);

        // Verify the expected hash value
        assert_eq!(
            result,
            "853867ce5b3bea173bc7b3b2c5f5f74445c9be20f9fcfe96eb65e2b9ce62fa29"
        );
    }

    #[test]
    fn test_sha256_hex_empty_input() {
        let input = b"";
        let result = sha256_hex(input);

        // SHA256 of empty string
        assert_eq!(
            result,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    mod zstd_tests {
        use super::zstd_example::*;

        #[test]
        fn test_compress_decompress() {
            let original = b"Hello, zstd compression! This is a test message.";
            let compressed = compress(original, 3).unwrap();
            let decompressed = decompress(&compressed).unwrap();

            assert_eq!(original.as_slice(), decompressed.as_slice());
        }

        #[test]
        fn test_streaming_compress_decompress() {
            let original = b"Streaming compression test with zstd-rs bindings.";
            let compressed = compress_streaming(original, 3).unwrap();
            let decompressed = decompress_streaming(&compressed).unwrap();

            assert_eq!(original.as_slice(), decompressed.as_slice());
        }

        #[test]
        fn test_compression_ratio() {
            // Repetitive data compresses well
            let repetitive_data = "Hello ".repeat(1000);
            let stats = compression_stats(repetitive_data.as_bytes(), 3).unwrap();

            // Repetitive data should compress to less than 10% of original size
            assert!(stats.compression_ratio > 10.0);
            assert!(stats.compressed_size < stats.original_size / 10);
        }

        #[test]
        fn test_empty_data() {
            let empty: &[u8] = b"";
            let compressed = compress(empty, 3).unwrap();
            let decompressed = decompress(&compressed).unwrap();

            assert!(decompressed.is_empty());
        }
    }
}
