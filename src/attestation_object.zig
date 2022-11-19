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
const EcdsaPubKey = @import("crypto.zig").EcdsaPubKey;
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
    credential_public_key: EcdsaPubKey,

    pub fn encode(self: *const @This(), out: anytype) !void {
        try out.writeAll(self.aaguid[0..]);
        // length is encoded in big-endian format
        try out.writeByte(@intCast(u8, self.credential_length >> 8));
        try out.writeByte(@intCast(u8, self.credential_length & 0xff));
        try out.writeAll(self.credential_id[0..]);
        try cbor.stringify(self.credential_public_key, .{}, out);
    }
};

/// The authenticator data structure encodes contextual bindings
/// made by the authenticator.
///
/// https://www.w3.org/TR/webauthn/#sctn-authenticator-data
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

    pub fn encode(self: *const @This(), out: anytype) !void {
        try out.writeAll(self.rp_id_hash[0..]);
        try out.writeByte(@bitCast(u8, self.flags));

        // counter is encoded in big-endian format
        try out.writeByte(@intCast(u8, (self.sign_count >> 24) & 0xff));
        try out.writeByte(@intCast(u8, (self.sign_count >> 16) & 0xff));
        try out.writeByte(@intCast(u8, (self.sign_count >> 8) & 0xff));
        try out.writeByte(@intCast(u8, self.sign_count & 0xff));

        try self.attested_credential_data.encode(out);

        // TODO: also encode extensions
    }
};
/// WebAuthn Attestation Statement Format Identifiers
///
/// https://www.w3.org/TR/webauthn/#sctn-defined-attestation-formats
pub const Fmt = enum {
    /// The "packed" attestation statement format is a WebAuthn-optimized format for attestation. It uses a very compact but still extensible encoding method. This format is implementable by authenticators with limited resources (e.g., secure elements).
    @"packed",
    /// The TPM attestation statement format returns an attestation statement in the same format as the packed attestation statement format, although the rawData and signature fields are computed differently.
    tpm,
    /// Platform authenticators on versions "N", and later, may provide this proprietary "hardware attestation" statement.
    @"android-key",
    /// Android-based platform authenticators MAY produce an attestation statement based on the Android SafetyNet API.
    @"android-safetynet",
    /// Used with FIDO U2F authenticators
    @"fido-u2f",
    /// Used with Apple devices' platform authenticators
    apple,
    /// Used to replace any authenticator-provided attestation statement when a WebAuthn Relying Party indicates it does not wish to receive attestation information.
    none,
};

/// https://www.w3.org/TR/webauthn/#sctn-attestation
pub const AttestationObject = struct {
    /// fmt
    @"1": Fmt,
    /// authData
    @"2": AuthData,
    /// attStmt
    @"3": AttStmt,

    // TODO: how to tell cbor stringify() to call encode instead???

    //pub fn encode(self: *const @This(), allocator: Allocator) ![]u8 {
    //    var ret = std.ArrayList(u8).init(allocator);
    //    errdefer ret.deinit();
    //    var wret = ret.writer();
    //    var ad = std.ArrayList(u8).init(allocator);
    //    defer ad.deinit();
    //    var wad = ad.writer();
    //    var pairs: [3]Pair = undefined;

    //    pairs[0] = Pair.new(DataItem{ .text = "fmt" }, DataItem{ .text = self.fmt.toString() });

    //    pairs[1] = Pair.new(DataItem{ .text = "attStmt" }, self.att_stmt.toCbor());

    //    try self.auth_data.encode(wad);
    //    pairs[2] = Pair.new(DataItem{ .text = "authData" }, DataItem{ .bytes = ad.items });

    //    const di = DataItem{ .map = pairs[0..] };
    //    try cbor.encode(wret, &di);

    //    return ret.toOwnedSlice();
    //}
};

// see: https://www.w3.org/TR/webauthn/#sctn-defined-attestation-formats

pub const AttStmtTag = enum { none };

pub const AttStmt = union(AttStmtTag) {
    none: bool,

    pub fn toCbor(self: @This()) DataItem {
        switch (self) {
            .none => {
                return DataItem.new(""); // map
            },
        }
    }
};

test "attestation none" {
    const allocator = std.testing.allocator;

    const a = AttStmt{ .none = true };
    const di = a.toCbor();
    _ = di;
    _ = allocator;

    //const c = try cbor.encodeAlloc(allocator, &di);
    //defer allocator.free(c);

    //try std.testing.expectEqualStrings("\xA0", c);
}

test "attestation credential data" {
    const allocator = std.testing.allocator;
    var a = std.ArrayList(u8).init(allocator);
    defer a.deinit();

    const acd = AttestedCredentialData{
        .aaguid = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .credential_length = 0x0040,
        .credential_id = &.{ 0xb3, 0xf8, 0xcd, 0xb1, 0x80, 0x20, 0x91, 0x76, 0xfa, 0x20, 0x1a, 0x51, 0x6d, 0x1b, 0x42, 0xf8, 0x02, 0xa8, 0x0d, 0xaf, 0x48, 0xd0, 0x37, 0x88, 0x21, 0xa6, 0xfb, 0xdd, 0x52, 0xde, 0x16, 0xb7, 0xef, 0xf6, 0x22, 0x25, 0x72, 0x43, 0x8d, 0xe5, 0x85, 0x7e, 0x70, 0xf9, 0xef, 0x05, 0x80, 0xe9, 0x37, 0xe3, 0x00, 0xae, 0xd0, 0xdf, 0xf1, 0x3f, 0xb6, 0xa3, 0x3e, 0xc3, 0x8b, 0x81, 0xca, 0xd0 },
        .credential_public_key = EcdsaPubKey.new(try Ecdsa.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52")),
    };

    var w = a.writer();
    try acd.encode(w);

    try std.testing.expectEqualSlices(u8, a.items, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40\xb3\xf8\xcd\xb1\x80\x20\x91\x76\xfa\x20\x1a\x51\x6d\x1b\x42\xf8\x02\xa8\x0d\xaf\x48\xd0\x37\x88\x21\xa6\xfb\xdd\x52\xde\x16\xb7\xef\xf6\x22\x25\x72\x43\x8d\xe5\x85\x7e\x70\xf9\xef\x05\x80\xe9\x37\xe3\x00\xae\xd0\xdf\xf1\x3f\xb6\xa3\x3e\xc3\x8b\x81\xca\xd0\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
}

test "authData encoding" {
    const allocator = std.testing.allocator;
    var a = std.ArrayList(u8).init(allocator);
    defer a.deinit();

    const acd = AttestedCredentialData{
        .aaguid = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .credential_length = 0x0040,
        .credential_id = &.{ 0xb3, 0xf8, 0xcd, 0xb1, 0x80, 0x20, 0x91, 0x76, 0xfa, 0x20, 0x1a, 0x51, 0x6d, 0x1b, 0x42, 0xf8, 0x02, 0xa8, 0x0d, 0xaf, 0x48, 0xd0, 0x37, 0x88, 0x21, 0xa6, 0xfb, 0xdd, 0x52, 0xde, 0x16, 0xb7, 0xef, 0xf6, 0x22, 0x25, 0x72, 0x43, 0x8d, 0xe5, 0x85, 0x7e, 0x70, 0xf9, 0xef, 0x05, 0x80, 0xe9, 0x37, 0xe3, 0x00, 0xae, 0xd0, 0xdf, 0xf1, 0x3f, 0xb6, 0xa3, 0x3e, 0xc3, 0x8b, 0x81, 0xca, 0xd0 },
        .credential_public_key = EcdsaPubKey.new(try Ecdsa.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52")),
    };

    const ad = AuthData{
        .rp_id_hash = .{ 0x21, 0x09, 0x18, 0x5f, 0x69, 0x3a, 0x01, 0xea, 0x1a, 0x26, 0x41, 0xf8, 0x2d, 0x52, 0xfb, 0xae, 0xee, 0x0a, 0x4f, 0x47, 0xe3, 0x37, 0x4d, 0xfe, 0xf8, 0x70, 0x83, 0x8d, 0xe4, 0x9b, 0x0e, 0x97 },
        .flags = Flags{
            .up = 1,
            .rfu1 = 0,
            .uv = 0,
            .rfu2 = 0,
            .at = 1,
            .ed = 0,
        },
        .sign_count = 0,
        .attested_credential_data = acd,
        .extensions = &.{},
    };

    var w = a.writer();
    try ad.encode(w);

    try std.testing.expectEqualSlices(u8, a.items, "\x21\x09\x18\x5f\x69\x3a\x01\xea\x1a\x26\x41\xf8\x2d\x52\xfb\xae\xee\x0a\x4f\x47\xe3\x37\x4d\xfe\xf8\x70\x83\x8d\xe4\x9b\x0e\x97\x41\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40\xb3\xf8\xcd\xb1\x80\x20\x91\x76\xfa\x20\x1a\x51\x6d\x1b\x42\xf8\x02\xa8\x0d\xaf\x48\xd0\x37\x88\x21\xa6\xfb\xdd\x52\xde\x16\xb7\xef\xf6\x22\x25\x72\x43\x8d\xe5\x85\x7e\x70\xf9\xef\x05\x80\xe9\x37\xe3\x00\xae\xd0\xdf\xf1\x3f\xb6\xa3\x3e\xc3\x8b\x81\xca\xd0\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
}

//test "attestationObject encoding - no attestation" {
//    const allocator = std.testing.allocator;
//
//    const acd = AttestedCredentialData{
//        .aaguid = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
//        .credential_length = 0x0040,
//        .credential_id = &.{ 0xb3, 0xf8, 0xcd, 0xb1, 0x80, 0x20, 0x91, 0x76, 0xfa, 0x20, 0x1a, 0x51, 0x6d, 0x1b, 0x42, 0xf8, 0x02, 0xa8, 0x0d, 0xaf, 0x48, 0xd0, 0x37, 0x88, 0x21, 0xa6, 0xfb, 0xdd, 0x52, 0xde, 0x16, 0xb7, 0xef, 0xf6, 0x22, 0x25, 0x72, 0x43, 0x8d, 0xe5, 0x85, 0x7e, 0x70, 0xf9, 0xef, 0x05, 0x80, 0xe9, 0x37, 0xe3, 0x00, 0xae, 0xd0, 0xdf, 0xf1, 0x3f, 0xb6, 0xa3, 0x3e, 0xc3, 0x8b, 0x81, 0xca, 0xd0 },
//        .credential_public_key = try Ecdsa.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52"),
//    };
//
//    const ad = AuthData{
//        .rp_id_hash = .{ 0x21, 0x09, 0x18, 0x5f, 0x69, 0x3a, 0x01, 0xea, 0x1a, 0x26, 0x41, 0xf8, 0x2d, 0x52, 0xfb, 0xae, 0xee, 0x0a, 0x4f, 0x47, 0xe3, 0x37, 0x4d, 0xfe, 0xf8, 0x70, 0x83, 0x8d, 0xe4, 0x9b, 0x0e, 0x97 },
//        .flags = Flags{
//            .up = 1,
//            .rfu1 = 0,
//            .uv = 0,
//            .rfu2 = 0,
//            .at = 1,
//            .ed = 0,
//        },
//        .sign_count = 0,
//        .attested_credential_data = acd,
//        .extensions = &.{},
//    };
//
//    const ao = AttestationObject{
//        .fmt = Fmt.none,
//        .att_stmt = AttStmt{ .none = true },
//        .auth_data = ad,
//    };
//
//    const data = try ao.encode(allocator);
//    defer allocator.free(data);
//
//    try std.testing.expectEqualSlices(u8, data, "\xa3\x63\x66\x6d\x74\x64\x6e\x6f\x6e\x65\x67\x61\x74\x74\x53\x74\x6d\x74\xa0\x68\x61\x75\x74\x68\x44\x61\x74\x61\x58\xc4\x21\x09\x18\x5f\x69\x3a\x01\xea\x1a\x26\x41\xf8\x2d\x52\xfb\xae\xee\x0a\x4f\x47\xe3\x37\x4d\xfe\xf8\x70\x83\x8d\xe4\x9b\x0e\x97\x41\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40\xb3\xf8\xcd\xb1\x80\x20\x91\x76\xfa\x20\x1a\x51\x6d\x1b\x42\xf8\x02\xa8\x0d\xaf\x48\xd0\x37\x88\x21\xa6\xfb\xdd\x52\xde\x16\xb7\xef\xf6\x22\x25\x72\x43\x8d\xe5\x85\x7e\x70\xf9\xef\x05\x80\xe9\x37\xe3\x00\xae\xd0\xdf\xf1\x3f\xb6\xa3\x3e\xc3\x8b\x81\xca\xd0\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
//}
