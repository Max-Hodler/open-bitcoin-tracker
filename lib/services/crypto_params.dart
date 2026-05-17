import 'package:cryptography/cryptography.dart';

/// Shared Argon2id parameters for PIN hashing (auth) and KEK derivation
/// (crypto). Keeping these identical means a verify and an unwrap take the
/// same wall time on the same device — important so timing observers can't
/// tell the two paths apart, and so PIN-cost UX is consistent across flows.
///
/// Values are OWASP's mobile profile (~150–250 ms on a midrange phone):
///   - parallelism: 1
///   - memory:      19456 KiB
///   - iterations:  2
///   - hashLength:  32 bytes
Argon2id buildStacksArgon2id() => Argon2id(
      parallelism: 1,
      memory: 19456,
      iterations: 2,
      hashLength: 32,
    );
