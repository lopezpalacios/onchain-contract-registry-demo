"""Minimal dependency-free Keccak-256 (Ethereum hash, not NIST SHA3-256)."""

MASK = 0xFFFFFFFFFFFFFFFF

ROUND_CONSTANTS = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]

ROTATIONS = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]


def _rol(value, shift):
    if shift == 0:
        return value & MASK
    return ((value << shift) | (value >> (64 - shift))) & MASK


def _keccak_f(state):
    for rc in ROUND_CONSTANTS:
        c = [state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                state[x + 5 * y] ^= d[x]

        b = [0] * 25
        for x in range(5):
            for y in range(5):
                b[y + 5 * ((2 * x + 3 * y) % 5)] = _rol(state[x + 5 * y], ROTATIONS[x][y])

        for x in range(5):
            for y in range(5):
                state[x + 5 * y] = (
                    b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y])
                ) & MASK

        state[0] ^= rc
    return state


def keccak256(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    rate = 136
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate != rate - 1:
        padded.append(0x00)
    padded.append(0x80)

    state = [0] * 25
    for offset in range(0, len(padded), rate):
        block = padded[offset:offset + rate]
        for lane in range(rate // 8):
            state[lane] ^= int.from_bytes(block[lane * 8:(lane + 1) * 8], "little")
        state = _keccak_f(state)

    return b"".join(state[i].to_bytes(8, "little") for i in range(4)).hex()


def keccak256_bytes(data):
    return bytes.fromhex(keccak256(data))


def selector(signature):
    return "0x" + keccak256(signature)[:8]


def topic(signature):
    return "0x" + keccak256(signature)


def eip55(address):
    raw = address.lower().replace("0x", "")
    if len(raw) != 40:
        raise ValueError("address must be 20 bytes")
    digest = keccak256(raw)
    checksummed = "".join(
        ch.upper() if ch in "abcdef" and int(digest[i], 16) >= 8 else ch
        for i, ch in enumerate(raw)
    )
    return "0x" + checksummed


def address_from_label(label):
    return "0x" + keccak256(label)[:40]


if __name__ == "__main__":
    assert keccak256(b"") == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    assert keccak256(b"abc") == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
    assert selector("transfer(address,uint256)") == "0xa9059cbb"
    assert topic("Transfer(address,address,uint256)") == (
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    )
    assert eip55("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") == (
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    )
    print("keccak self-test ok")
