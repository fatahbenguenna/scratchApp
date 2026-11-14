import Foundation

/// Empreinte SHA-256 (FIPS 180-4) en Swift pur, sans CryptoKit ni CommonCrypto (ADR-09, D-43,
/// NFR9) : un seul code, aux résultats identiques sous Linux et sur les plateformes Apple.
///
/// Calcul incrémental : `update(_:)` autant de fois que nécessaire, puis `finalize()`. Les blocs
/// complets de 64 octets sont compressés directement depuis la mémoire de l'appelant ; seul le reste
/// (moins de 64 octets) est conservé d'un appel à l'autre. Arithmétique modulo 2³² (`&+`), rotations
/// sur `UInt32`, tableau de 64 mots réutilisé pour tous les blocs d'un même appel.
struct SHA256 {
    /// Taille d'un bloc de compression, en octets.
    static let blockSize = 64
    /// Taille de l'empreinte, en octets.
    static let digestSize = 32

    /// Les huit mots de l'état de hachage (H0 à H7).
    private struct State {
        var h0: UInt32 = 0x6a09_e667, h1: UInt32 = 0xbb67_ae85, h2: UInt32 = 0x3c6e_f372, h3: UInt32 = 0xa54f_f53a
        var h4: UInt32 = 0x510e_527f, h5: UInt32 = 0x9b05_688c, h6: UInt32 = 0x1f83_d9ab, h7: UInt32 = 0x5be0_cd19
    }

    private var state = State()
    // Bytes waiting for a full block (always fewer than blockSize).
    private var pending: [UInt8] = []
    // Total message length in bytes.
    private var messageLength: UInt64 = 0

    init() {
        pending.reserveCapacity(Self.blockSize)
    }

    /// Ajoute des octets au message.
    mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    /// Ajoute des octets au message.
    mutating func update(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { update($0) }
    }

    /// Ajoute des octets au message.
    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress, !bytes.isEmpty else { return }
        messageLength &+= UInt64(bytes.count)
        var offset = 0
        var state = self.state
        if !pending.isEmpty {
            let take = min(Self.blockSize - pending.count, bytes.count)
            pending.append(contentsOf: UnsafeRawBufferPointer(start: base, count: take))
            offset = take
            if pending.count == Self.blockSize {
                pending.withUnsafeBytes { Self.compress(blocks: $0.baseAddress!, count: 1, state: &state) }
                pending.removeAll(keepingCapacity: true)
            }
        }
        let fullBlocks = (bytes.count - offset) / Self.blockSize
        if fullBlocks > 0 {
            Self.compress(blocks: base + offset, count: fullBlocks, state: &state)
            offset += fullBlocks * Self.blockSize
        }
        if offset < bytes.count {
            pending.append(contentsOf: UnsafeRawBufferPointer(start: base + offset, count: bytes.count - offset))
        }
        self.state = state
    }

    /// Empreinte du message reçu jusqu'ici (32 octets). Ne modifie pas l'état : d'autres octets
    /// peuvent encore être ajoutés ensuite.
    func finalize() -> [UInt8] {
        var copy = self
        let bitLength = messageLength &* 8
        let used = Int(messageLength % UInt64(Self.blockSize))
        // 0x80, zeros up to 56 mod 64, then the 64-bit big-endian bit length (FIPS 180-4 §5.1.1).
        var padding: [UInt8] = [0x80]
        padding.append(contentsOf: repeatElement(0, count: used < 56 ? 55 - used : 119 - used))
        for shift in stride(from: 56, through: 0, by: -8) {
            padding.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        copy.update(padding)
        assert(copy.pending.isEmpty)
        let s = copy.state
        var digest: [UInt8] = []
        digest.reserveCapacity(Self.digestSize)
        for word in [s.h0, s.h1, s.h2, s.h3, s.h4, s.h5, s.h6, s.h7] {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return digest
    }

    /// Empreinte d'un bloc de données en mémoire.
    static func hash(_ data: Data) -> [UInt8] {
        var hasher = SHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    /// Représentation hexadécimale minuscule (64 caractères pour une empreinte).
    static func hexString(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var characters: [UInt8] = []
        characters.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: characters, as: UTF8.self)
    }

    // MARK: - Compression (FIPS 180-4 §6.2.2)

    private static let roundConstants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    @inline(__always)
    private static func rotateRight(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x &>> n) | (x &<< (32 &- n))
    }

    /// Compresse `count` blocs consécutifs de 64 octets (sans contrainte d'alignement).
    private static func compress(blocks: UnsafeRawPointer, count: Int, state: inout State) {
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { w in
            roundConstants.withUnsafeBufferPointer { k in
                var h0 = state.h0, h1 = state.h1, h2 = state.h2, h3 = state.h3
                var h4 = state.h4, h5 = state.h5, h6 = state.h6, h7 = state.h7
                var block = blocks
                for _ in 0 ..< count {
                    for t in 0 ..< 16 {
                        w[t] = UInt32(bigEndian: block.loadUnaligned(fromByteOffset: t &* 4, as: UInt32.self))
                    }
                    for t in 16 ..< 64 {
                        let x = w[t &- 15], y = w[t &- 2]
                        let s0 = rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x &>> 3)
                        let s1 = rotateRight(y, 17) ^ rotateRight(y, 19) ^ (y &>> 10)
                        w[t] = w[t &- 16] &+ s0 &+ w[t &- 7] &+ s1
                    }
                    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
                    for t in 0 ..< 64 {
                        let sigma1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                        let choice = (e & f) ^ (~e & g)
                        let t1 = h &+ sigma1 &+ choice &+ k[t] &+ w[t]
                        let sigma0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                        let majority = (a & b) ^ (a & c) ^ (b & c)
                        h = g
                        g = f
                        f = e
                        e = d &+ t1
                        d = c
                        c = b
                        b = a
                        a = t1 &+ sigma0 &+ majority
                    }
                    h0 &+= a; h1 &+= b; h2 &+= c; h3 &+= d
                    h4 &+= e; h5 &+= f; h6 &+= g; h7 &+= h
                    block += blockSize
                }
                state = State(h0: h0, h1: h1, h2: h2, h3: h3, h4: h4, h5: h5, h6: h6, h7: h7)
            }
        }
    }
}
