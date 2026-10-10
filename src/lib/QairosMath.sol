// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title QairosMath
/// @notice Scalar multiplication on short Weierstrass curves y^2 = x^3 + ax + b over a prime field.
///         Jacobian coordinates; a single modular inverse at the end. Works for any prime p < 2^256.
library QairosMath {
    struct Curve {
        uint256 p;
        uint256 a;
        uint256 b;
    }

    function _sub(uint256 x, uint256 y, uint256 p) private pure returns (uint256) {
        return addmod(x, p - (y % p), p);
    }

    function _double(uint256 X, uint256 Y, uint256 Z, uint256 a, uint256 p)
        private
        pure
        returns (uint256, uint256, uint256)
    {
        if (Y == 0 || Z == 0) return (0, 1, 0);
        uint256 YY = mulmod(Y, Y, p);
        uint256 S = mulmod(4, mulmod(X, YY, p), p);
        uint256 ZZ = mulmod(Z, Z, p);
        uint256 M = addmod(mulmod(3, mulmod(X, X, p), p), mulmod(a, mulmod(ZZ, ZZ, p), p), p);
        uint256 X3 = _sub(mulmod(M, M, p), mulmod(2, S, p), p);
        uint256 Y3 = _sub(mulmod(M, _sub(S, X3, p), p), mulmod(8, mulmod(YY, YY, p), p), p);
        uint256 Z3 = mulmod(2, mulmod(Y, Z, p), p);
        return (X3, Y3, Z3);
    }

    function _add(
        uint256 X1,
        uint256 Y1,
        uint256 Z1,
        uint256 X2,
        uint256 Y2,
        uint256 Z2,
        uint256 a,
        uint256 p
    ) private pure returns (uint256, uint256, uint256) {
        if (Z1 == 0) return (X2, Y2, Z2);
        if (Z2 == 0) return (X1, Y1, Z1);
        uint256 Z1Z1 = mulmod(Z1, Z1, p);
        uint256 Z2Z2 = mulmod(Z2, Z2, p);
        uint256 U1 = mulmod(X1, Z2Z2, p);
        uint256 U2 = mulmod(X2, Z1Z1, p);
        uint256 S1 = mulmod(Y1, mulmod(Z2, Z2Z2, p), p);
        uint256 S2 = mulmod(Y2, mulmod(Z1, Z1Z1, p), p);
        if (U1 == U2) {
            if (S1 != S2) return (0, 1, 0);
            return _double(X1, Y1, Z1, a, p);
        }
        uint256 H = _sub(U2, U1, p);
        uint256 R = _sub(S2, S1, p);
        uint256 HH = mulmod(H, H, p);
        uint256 HHH = mulmod(H, HH, p);
        uint256 V = mulmod(U1, HH, p);
        uint256 X3 = _sub(_sub(mulmod(R, R, p), HHH, p), mulmod(2, V, p), p);
        uint256 Y3 = _sub(mulmod(R, _sub(V, X3, p), p), mulmod(S1, HHH, p), p);
        uint256 Z3 = mulmod(H, mulmod(Z1, Z2, p), p);
        return (X3, Y3, Z3);
    }

    /// @dev Modular inverse via Fermat's little theorem using the MODEXP precompile (0x05).
    function inverse(uint256 x, uint256 p) internal view returns (uint256 r) {
        require(x % p != 0, "QairosMath: no inverse");
        bytes memory input = abi.encodePacked(uint256(32), uint256(32), uint256(32), x, p - 2, p);
        (bool ok, bytes memory out) = address(0x05).staticcall(input);
        require(ok && out.length == 32, "QairosMath: modexp failed");
        r = abi.decode(out, (uint256));
    }

    function isOnCurve(Curve memory c, uint256 x, uint256 y) internal pure returns (bool) {
        if (x >= c.p || y >= c.p) return false;
        uint256 lhs = mulmod(y, y, c.p);
        uint256 rhs = addmod(addmod(mulmod(mulmod(x, x, c.p), x, c.p), mulmod(c.a, x, c.p), c.p), c.b, c.p);
        return lhs == rhs;
    }

    /// @notice Returns k * (gx, gy). `infinity` is true when the result is the point at infinity.
    function mul(Curve memory c, uint256 k, uint256 gx, uint256 gy)
        internal
        view
        returns (uint256 x, uint256 y, bool infinity)
    {
        uint256 p = c.p;
        uint256 a = c.a % p;
        (uint256 RX, uint256 RY, uint256 RZ) = (0, 1, 0);
        (uint256 PX, uint256 PY, uint256 PZ) = (gx, gy, 1);
        while (k != 0) {
            if (k & 1 == 1) (RX, RY, RZ) = _add(RX, RY, RZ, PX, PY, PZ, a, p);
            (PX, PY, PZ) = _double(PX, PY, PZ, a, p);
            k >>= 1;
        }
        if (RZ == 0) return (0, 0, true);
        uint256 zi = inverse(RZ, p);
        uint256 zi2 = mulmod(zi, zi, p);
        x = mulmod(RX, zi2, p);
        y = mulmod(RY, mulmod(zi2, zi, p), p);
    }
}
