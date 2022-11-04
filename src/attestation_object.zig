// ATTESTATION OBJECT
// ________________________________________________________
// | "fmt": "fido-u2f" | "attStmt": ... | "authData": ... |
// --------------------------------------------------------
//                             |               |
//  ----------------------------               V
//  |
//  |     32 bytes      1        4            var             var
//  |  ____________________________________________________________
//  |  | RP ID hash | FLAGS | COUNTER | ATTESTED CRED. DATA | EXT |
//  |  ------------------------------------------------------------
//  |                    |                      |
//  |                    V                      |
//  |          _____________________            |
//  |          |ED|AT|0|0|0|UV|0|UP|            |
//  |          ---------------------            |
//  |                                           V
//  |          _______________________________________________
//  |          | AAGUID | L | CREDENTIAL ID | CRED. PUB. KEY |
//  |          -----------------------------------------------
//  |           16 bytes  2        L          var len (COSE key)
//  |
//  V                      __________________________________
// if Basic or Privacy CA: |"alg": ...|"sig": ...|"x5c": ...|
//                         ----------------------------------
//                         _______________________________________
// if ECDAA:               |"alg": ...|"sig": ...|"ecdaaKeyId": ..|
//                         ---------------------------------------

const std = @import("std");
const cbor = @import("zbor");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const DataItem = cbor.DataItem;
const Pair = cbor.Pair;
const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;

pub const Flags = packed struct(u8) {
    /// User Present (UP) result.
    /// - 1 means the user is present.
    /// - 0 means the user is not present.
    up: u1,
    /// Reserved for future use.
    rfu1: u1,
    /// User Verified (UV) result.
    /// - 1 means the user is verified.
    /// - 0 means the user is not verified.
    uv: u1,
    /// Reserved for future use.
    rfu2: u3,
    /// Attested credential data includet (AT).
    /// Indicates whether the authenticator added attested
    /// credential data.
    at: u1,
    /// Extension data included (ED).
    /// Indicates if the authenticator data has extensions.
    ed: u1,
};

/// Attested credential data is a variable-length byte array added
/// to the authenticator data (AuthData) when generating an
/// attestation object for a given credential.
pub const AttestedCredentialData = struct {
    /// The AAGUID of the authenticator.
    aaguid: [16]u8,
    /// Byte length L of Credential ID, 16-bit unsigned
    /// big-endian integer.
    credential_length: u16,
    /// Credential ID.
    credential_id: []const u8,
    /// The credential public key.
    credential_public_key: Ecdsa.PublicKey,

    pub fn encode(self: *const @This(), out: anytype) !void {
        try out.writeAll(self.aaguid[0..]);
        // length is encoded in big-endian format
        try out.writeByte(@intCast(u8, self.credential_length >> 8));
        try out.writeByte(@intCast(u8, self.credential_length & 0xff));
        try out.writeAll(self.credential_id[0..]);

        // Example key encoding
        // A5010203262001215820D9F4C2A352136F19C9A95DA8824AB5CDC4D5631EBCFD5BDBB0BFFF253609129E225820EF404B880765576007888A3ED6ABFFB4257B7123553325D450613CB5BC9A3A52
        // {1: 2, 3: -7, -1: 1, -2: h'D9F4C2A352136F19C9A95DA8824AB5CDC4D5631EBCFD5BDBB0BFFF253609129E', -3: h'EF404B880765576007888A3ED6ABFFB4257B7123553325D450613CB5BC9A3A52'}
    }
};

/// The authenticator data structure encodes contextual bindings
/// made by the authenticator.
pub const AuthData = struct {
    /// SHA-256 hash of the RPID (domain string) the credential
    /// is scoped to.
    rp_id_hash: [32]u8,
    flags: Flags,
    /// Signature counter, 32-bit unsigned big-endian integer.
    sign_count: u32,
    /// Attested credential data.
    attested_credential_data: AttestedCredentialData,
    /// Extensions-defined authenticator data.
    /// This is a CBOR map with extension identifiers as keys,
    /// and authenticator extension outputs as values.
    extensions: []const u8,
};

pub const AttestationObject = struct {
    fmt: []const u8,
    att_stmt: AttStmt,
    auth_data: AuthData,
};

// see: https://www.w3.org/TR/webauthn/#sctn-defined-attestation-formats

pub const AttStmtTag = enum { none };

pub const AttStmt = union(AttStmtTag) {
    none: bool,

    pub fn toCbor(self: @This()) DataItem {
        switch (self) {
            .none => {
                return DataItem{ .map = &.{} };
            },
        }
    }
};

test "attestation none" {
    const allocator = std.testing.allocator;

    const a = AttStmt{ .none = true };
    const di = a.toCbor();

    const c = try cbor.encodeAlloc(allocator, &di);
    defer allocator.free(c);

    try std.testing.expectEqualStrings("\xA0", c);
}
