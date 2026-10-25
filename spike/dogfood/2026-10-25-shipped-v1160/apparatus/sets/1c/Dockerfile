# Set 1's next reserve (transcripts/scout-1.txt): sqlx-cli 0.9.0, the latest on crates.io on
# 2026-10-25, built with SQLite only by the stable toolchain rustup answered that day (the project
# publishes no binary). The toolchain is removed after the build; the binary stays.
FROM sideeye-sv1025-s1b
RUN curl -fsSL https://sh.rustup.rs -o /tmp/rustup.sh && sh /tmp/rustup.sh -y --profile minimal > /tmp/rustup.log 2>&1 && echo "OK rustup $(/root/.cargo/bin/rustc --version)"
RUN /root/.cargo/bin/cargo install sqlx-cli --version 0.9.0 --locked --no-default-features --features sqlite,completions --root /opt/sqlx > /tmp/cargo-sqlx.log 2>&1 && echo "OK sqlx-cli" || { echo "FAILED sqlx-cli"; tail -20 /tmp/cargo-sqlx.log; }
RUN ln -sf /opt/sqlx/bin/sqlx /opt/bin/sqlx && ln -sf /opt/sqlx/bin/cargo-sqlx /opt/bin/cargo-sqlx && rm -rf /root/.cargo/registry /root/.rustup
RUN { cat /versions.txt; echo "sqlx $(sqlx --version 2>&1 | head -1)"; echo "link sqlx: $(file -bL /opt/bin/sqlx | cut -c1-90)"; } > /versions.new && mv /versions.new /versions.txt && tail -2 /versions.txt
