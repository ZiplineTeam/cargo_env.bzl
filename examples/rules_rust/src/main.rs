use cargo_env_examples::sha256_hex;
use cargo_env_examples::zstd_example;

fn main() {
    // OpenSSL example
    let input = b"hello openssl";
    let hex = sha256_hex(input);
    println!("sha256({:?}) = {}", String::from_utf8_lossy(input), hex);

    // Zstd compression example
    println!("\n--- Zstd Compression Example ---");
    let data = "Hello, zstd compression! ".repeat(100);
    let original_size = data.len();

    match zstd_example::compress(data.as_bytes(), 3) {
        Ok(compressed) => {
            println!("Original size: {} bytes", original_size);
            println!("Compressed size: {} bytes", compressed.len());
            println!(
                "Compression ratio: {:.2}x",
                original_size as f64 / compressed.len() as f64
            );

            // Verify round-trip
            if let Ok(decompressed) = zstd_example::decompress(&compressed) {
                println!(
                    "Round-trip successful: {} bytes decompressed",
                    decompressed.len()
                );
            }
        }
        Err(e) => eprintln!("Compression error: {}", e),
    }
}
