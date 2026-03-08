
            /// Returns the `rustc` SemVer version and additional metadata
            /// like the git short hash and build date.
            pub fn version_meta() -> VersionMeta {
                VersionMeta {
                    semver: Version {
                        major: 1,
                        minor: 92,
                        patch: 0,
                        pre: Prerelease::new("").unwrap(),
                        build: BuildMetadata::new("").unwrap(),
                    },
                    host: "aarch64-apple-darwin".to_owned(),
                    short_version_string: "rustc 1.92.0 (ded5c06cf 2025-12-08)".to_owned(),
                    commit_hash: Some("ded5c06cf21d2b93bffd5d884aa6e96934ee4234".to_owned()),
                    commit_date: Some("2025-12-08".to_owned()),
                    build_date: None,
                    channel: Channel::Stable,
                    llvm_version: Some(LlvmVersion{ major: 21, minor: 1 }),
                }
            }
            