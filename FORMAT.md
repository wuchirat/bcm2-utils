File format specification
=========================

This document describes the format used to store configuration data
in permnv/dynnv and the firmware settings dump (aka `GatewaySettings.bin`).

All numbers are stored in network byte order (big endian).

Header
------

### Permnv/dynnv

| Offset | Type         | Name       | Comment            |
|-------:|--------------|------------|--------------------|
|    `0` | `byte[202]`  | `magic`    | all `\xff`         |
|  `202` | `u32`        | `size`     |                    |
|  `206` | `u32`        | `checksum` |                    |
|  `210` |`byte[size-8]`| `data`     |                    |

To calculate the checksum, `checksum` is first set to zero,
then, starting at `size`, the following algorithm is employed:

```
uint32_t checksum(const char* buf)
{
	uint32_t checksum = 0;

	uint32_t word;
	while (read_next_word(buf, &word)) {
		checksum += word;
	}

	uint16_t half;
	if (!read_next_half(buf, &half)) {
		half = 0;
	}

	uint8_t byte;
	if (!read_next_byte(buf, &byte)) {
		byte = 0;
	}

	checksum += (byte | (half << 8)) << 8;
	return ~checksum;
}
```

For a buffer containing the data `\xaa\xaa\xaa\xaa\xbb\xbb\xbb\xbb\xcc\xcc\xdd`, the
checksum is thus `~(0xaaaaaaaa + 0xbbbbbbbb + 0xccccdd00)`, for `\xaa\xaa\xaa\xaa\xbb`,
it would be `~(0xaaaaaaaa + 0x0000bb00)` (assuming `uint32_t` rollover on overflow).

### GatewaySettings.bin (standard)

| Offset  | Type        | Name       | Comment              |
|--------:|-------------|------------|----------------------|
|    `0`  | `byte[16]`  | `checksum` ||
|   `16`  | `string[74]`| `magic`    | Vendor specific (?)  |
|   `90`  | `byte[2]`   | ?          | Assumed to be a version (always `0.0`) |
|   `92`  | `u32`       | `size`     ||
|   `96`  | `byte[size]`| `data`     ||
|`96+size`| `byte[16]`  | `padding`  | Found in some encrypted files (all `\x00`) |

Currently known magic values:

| Vendor              | Magic                                                                        |
|---------------------|------------------------------------------------------------------------------|
| Technicolor/Thomson | `6u9E9eWF0bt9Y8Rw690Le4669JYe4d-056T9p4ijm4EA6u9ee659jn9E-54e4j6rPj069K-670` |
| Netgear             | `6u9e9ewf0jt9y85w690je4669jye4d-056t9p48jp4ee6u9ee659jy9e-54e4j6r0j069k-056` |

The checksum is an MD5 hash, calculated from the file contents immediately after the checksum (i.e.
*everything* but the first 16 bytes). To calculate the checksum, a 16-byte device-specific key is added
to the data; for some devices, this is easily guessed (Thomson TWG850-4: `TMM_TWG850-4\x00\x00\x00\x00`,
Techicolor TC7200: `TMM_TC7200\x00\x00\x00\x00\x00\x00`), for others, it must be extracted from a firmware dump
(e.g. Netgear CG3000: `\x32\x50\x73\x6c\x63\x3b\x75\x28\x65\x67\x6d\x64\x30\x2d\x27\x78`).


###### Encryption (Thomson, Technicolor)
On some devices, all data *after* the checksum is encrypted using AES-256 in ECB mode. This means that the
checksum can be validated even if the encryption key is not known.

All currently known devices have a default encryption key, and some allow specifying a backup password. If the
final block is less than 16 bytes, the data is copied verbatim, thus leaking some information:

```
...
000041a0  80 d3 e4 8a 71 51 f2 64  81 e4 31 4a 64 a9 5d 74  |....qQ.d..1Jd.]t|
000041b0  69 6e 00 05 61 64 6d 69  6e                       |in..admin|
```

Some firmware versions append a 16-byte block of all `\x00` before encrypting, so as to "leak" only
zeroes:

```
...
000041a0  80 d3 e4 8a 71 51 f2 64  81 e4 31 4a 64 a9 5d 74  |....qQ.d..1Jd.]t|
000041b0  b3 65 87 cd ad 42 6c d1  af 3c 63 a9 20 b1 b9 6c  |.e...Bl..<c. ..l|
000041c0  00 00 00 00 00 00 00 00  00                       |.........|
```

###### Encryption (Netgear, Asus (?))
Some Netgear and possibly Asus devices encrypt the *whole* file using 3DES in ECB mode. In contrast to
the other encryption method described above, the checksum of these files can only be validated *after*
decryption.

If the final block is less than 16 (or 8?) bytes, the data is padded to 15 (or 7?) bytes using zeroes.
The last byte contains the number of zero bytes used for padding. For example, the block
```
000041b0  69 6e 00 05 61 64 6d 69  6e                       |in..admin|
```
would be padded to
```
000041b0  69 6e 00 05 61 64 6d 69  6e 00 00 00 00 00 00 06  |in..admin.......|
```



### GatewaySettings.bin (dynnv)

| Offset | Type         | Name       | 
|-------:|--------------|------------|
|  `0`   | `u32`        | `size`     |
|  `4`   | `u32`        | `checksum` |
|  `8`   |`byte[size-8]`| `data`     |

The header for this file format is the same as for `permnv` and `dynnv`, minus
the 202-byte all `\xff` header. 

###### Encryption

A primitive (and obvious) subtraction cipher with 16 keys is sometimes used. The keys are:

```
00 00 02 00 04 00 06 00 08 00 0a 00 0c 00 0e 00
10 00 12 00 14 00 16 00 18 00 1a 00 1c 00 1e 00
20 00 22 00 24 00 26 00 28 00 2a 00 2c 00 2e 00
...
f0 00 f2 00 f4 00 f6 00 f8 00 fa 00 fc 00 fe 00
```
For the first 16-byte block, the first key is used, the second key for the second block,
and so forth. For the 17th block, the first key is used again. After decryption, 
bytes `n` and `n+1` (`n` being an even number, including zero) are swapped in each
16-byte block.

If the last block is less than 16 bytes, it is copied verbatim. A 36 byte all-zero file
would thus be encrypted as

```
00 00 02 00 04 00 06 00 08 00 0a 00 0c 00 0e 00
10 00 12 00 14 00 16 00 18 00 1a 00 1c 00 1e 00
00 00 00 00
```

Configuration data
------------------

Aside from the header, `GatewaySettings.bin` and permnv/dynnv use the same format. The
configuration data consists of a series of settings groups, each preceeded by a group
header.

### Group header

| Offset | Type          | Name       |
|-------:|---------------|------------|
|    `0` | `u16`         | `size`     |
|    `4` | `byte[4]`     | `magic`    |
|    `6` | `byte[2]`     | `version`  |
|    `8` | `byte[size-8]`| `data`     |

Value of `size` is the number of bytes in this group, including the full header. An empty
settings group's size is thus `8` bytes. The `magic` is often either a human-readable string
(`802T`: Thomson Wi-Fi settings, `CMEV`: CM event log) or a hexspeak `u32` (`0xd0c20130`: DOCSIS 3.0 settings,
`0xf2a1f61f`: HAL interface settings).

### Group data

Since the groups contain variable-length values, to interpret a specific variable, the type of all preceeding
variables must be known. Within the same device, newer group versions will place new variables at the end, but
this may not be true for group data on different devices.

##### Data types

###### Numbers

Always stored in network byte order; `uN` for unsigned N-bit integers, `iN` for signed N-bit integers. Enum and
bitmask types based on `uN` types are also available.

###### Strings

Various methods are used to store strings, with some groups often showing a preference for one kind of encoding.
The following table shows various string samples (`\x??` means *any* byte, `(N)` means width `N`):

| Type       | Description                                 | `""`               | `"foo"`                        |
| -----------|---------------------------------------------|--------------------|--------------------------------|
|`fstring`   | Fixed-width string, with optional NUL byte  | `\x00\x00`(2)   |`foo`(3), `foo\x00\x??\x??`(6)|
|`fzstring`  | Fixed-width string, with mandatory NUL byte | `\x00\x00`(2)   | `foo\x00`(4), `foo\x00:??`(5)|
|`zstring`   | NUL-terminated string                       | `\x00`             | `foo\x00`                      |
|`p8string`  | `u8`-prefixed string, with optional NUL byte| `\x00`             |`\x03foo`, `\x04foo\x00`        |
|`p8zstring` | `u8`-prefixed string with mandatory NUL byte| `\x00`             | `\x04foo\x00`                  |
|`p8istring` | `u8`-prefixed string with optional NUL byte, size includes prefix | `\x00` | `\x04foo`, `\x05foo\x00`|
|`p16string` | `u16`-prefixed string, with optional NUL byte | `\x00\x00`       |`\x00\x03foo`, `\x00\x04foo\x00`|
|`p16zstring`| `u16`-prefixed string with mandatory NUL byte | `\x00\x00`       |`\x00\x04foo\x00`               |
|`p16istring`| `u16`-prefixed string with optional NUL byte, size includes prefix |`\x00\x00`| `\x00\x05foo`,`\x00\x06foo\x00`|

###### Lists

| Type       | Description                                                                    |                           
| -----------|--------------------------------------------------------------------------------|
| `array`    | Fixed-size array (element number is fixed, but not actual size in bytes)       |
| `pNlist`   | `u8`- or `u16`-prefixed list; prefix contains number of elements in list       |

Even though an `array` always has a fixed length defined in code, some elements may be considered
undefined, i.e. the *apparent* length of the array may be less. In some settings groups, "dummy"
entries are used to mark undefined elements (e.g. MAC adddress `00:00:00:00:00:00`, IPv4 `0.0.0.0`,
string `""`, etc.) while in others, the apparent length is stored in another variable within the
same group (but not as a prefix).

Sample encodings for string arrays/lists:

| Type                   | `{ "foo", "ba", "r" }`            | `{ "", "" }`                       |          
|------------------------|-----------------------------------|------------------------------------|
| `array<fzstring<4>>`   | `foo\x00ba\x00\x00r\x00\x00\x00`  | `\x00\x00\x00\x00\x00\x00\x00\x00` |                           
| `array<zstring>`       | `foo\x00ba\x00r\x00`              | `\x00\x00`                         |
| `array<p8string>`      | `\x03foo\x02ba\x01r`              | `\x00\x00`                         |
| `p8list<zstring>`      | `\x03foo\x00ba\x00r\x00`          | `\x02\x00\x00`                     |
| `p8list<p8string>`     | `\x03\x03foo\x02ba\x01r`          | `\x02\x00\x00`                     |
| `p16list<fstring<3>>`  | `\x00\x03fooba\x00r\x00\x00`      | `\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00` |

Sample encodings for integer arrays/lists:

| Type                   | `{ 0xaaaa, 0, 0xbbbb  }`                   | `{ 0xaa }`, width 2, dummy `0` | `{}`      |        
|------------------------|--------------------------------------------|--------------------------------|-----------|
| `array<u16>`           | `\xaa\xaa\x00\x00\xbb\xbb`                 |`\x00\xaa\x00\x00`              | N/A       |
| `array<u32>`           | `\x00\x00\xaa\xaa\x00\x00\x00\x00\xbb\xbb` |`\x00\x00\x00\xaa\x00\x00\x00\x00`| N/A     |
| `p8list<u16>`          | `\x03\xaa\xaa\x00\x00\xbb\xbb`             | N/A                            | `\x00`    | 
| `p16list<u16>`         | `\x00\x03\xaa\xaa\x00\x00\xbb\xbb`         | N/A                            | `\x00\x00`| 















